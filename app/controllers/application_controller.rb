#encoding: utf-8
# Filters added to this controller apply to all controllers in the application.
# Likewise, all the methods added will be available for all controllers.

class ApplicationController < ActionController::Base
  include NotificationHelper
  helper :all # include all helpers, all the time
  protect_from_forgery # See ActionController::RequestForgeryProtection for details
  after_filter :discard_flash_if_xhr

  before_filter :store_location #salvo l'indirizzo dal quale provengo
  before_filter :set_locale
    
  before_filter :prepare_for_mobile

  def extract_locale_from_tld

  end
 
  def set_locale
    @domain_locale = request.host.split('.').last
    I18n.locale =
      (Rails.env == :staging ?
       params[:l] || I18n.default_locale :
       params[:l] || @domain_locale || I18n.default_locale)

  end
  
  def default_url_options(options={})
    #return {} if extract_locale_from_tld
    #return {} if params[:l] == I18n.default_locale
    #logger.debug "default_url_options is passed options: #{options.inspect}\n"
    (!params[:l] || (params[:l] == @domain_locale)) ? {} : {:l => I18n.locale }
  end
  
  helper_method :is_admin?, :is_proprietary?, :current_url, :link_to_auth, :mobile_device?, :age

  
   def log_error(exception)
     notifier = Rails.application.config.middleware.detect { |x| x.klass == ExceptionNotifier }
    if notifier
      env = request.env
      env['exception_notifier.options'] = notifier.args.first || {}                   
      ExceptionNotifier::Notifier.exception_notification(env, exception).deliver
      env['exception_notifier.delivered'] = true
    end
    message = "\n#{exception.class} (#{exception.message}):\n"
    Rails.logger.error(message)
  end
  
  
  def render_error(exception)
    log_error(exception)
    render :template => "/errors/500.html.erb", :status => 500
  end
  
  def render_404(exception=nil)
    log_error(exception) if exception
    respond_to do |format|
      format.html { render "errors/404", :status => 404, :layout => true }
      #format.xml  { render :nothing => true, :status => '404 Not Found' }
    end
    true
  end

  
  def current_url(overwrite={})
    url_for params.merge(overwrite).merge(:only_path => false)
  end
  
  #helper method per determinare se l'utente attualmente collegato è amministratore di sistema
  def is_admin? 
    if user_signed_in? && current_user.user_type.short_name == "admin"
      true
    else
      false
    end
  end
  
  #helper method per determinare se l'utente attualmente collegato è il proprietario di un determinato oggetto
  def is_proprietary?(object)
    if (current_user && current_user.is_mine?(object))
      return true
    else
      return false
    end      
  end

  def age(birthdate)
    today = Date.today
    puts 'today: ' + today.to_s
    # Difference in years, less one if you have not had a birthday this year.
    a = today.year - birthdate.year
    a = a - 1 if (
         birthdate.month >  today.month or 
        (birthdate.month >= today.month and birthdate.day > today.day)
    )
    a
  end

  
  def link_to_auth (text, link)
      return "<a>login</a>"
  end
  
  def title(ttl)
    @page_title = ttl
  end


  
  def admin_required
    is_admin? || admin_denied
  end
  
  #risposta nel caso sia necessario essere amministartori
  def admin_denied
    respond_to do |format|
      format.js do        #se era una chiamata ajax, mostra il messaggio
        flash.now[:notice] = t('error.admin_required')
        render :update do |page|
           page.replace_html "flash_messages", :partial => 'layouts/flash', :locals => {:flash => flash}
        end  
      end
      format.html do   #ritorna indietro oppure all'HomePage
        store_location
        flash[:error] = t('error.admin_required')
        if request.env["HTTP_REFERER"]
          redirect_to :back
        else
          redirect_to proposals_path
        end        
      end
    end
  end
  
  #risposta generica nel caso non si abbiano i privilegi per eseguire l'operazione
  def permissions_denied
    respond_to do |format|
      format.js do        #se era una chiamata ajax, mostra il messaggio
        flash.now[:notice] = t('error.permissions_required')
        render :update do |page|
           page.replace_html "flash_messages", :partial => 'layouts/flash', :locals => {:flash => flash}
        end  
      end
      format.html do   #ritorna indietro oppure all'HomePage
        store_location
        flash[:notice] = t('error.permissions_required')
        if request.env["HTTP_REFERER"]
          redirect_to :back
        else
          redirect_to proposals_path
        end        
      end
    end
  end
  
  #salva l'url
  def store_location
    #if (params[:controller] == "proposal_comments" && params[:action] == "create")
    #  session[:user_return_to] = request.url
    #  return
    #end
     unless (request.xhr? || 
             (!params[:controller]) ||
             (params[:controller].starts_with? "devise/") ||
             (params[:controller] == "users/omniauth_callbacks") || 
             (params[:controller] == "alerts" && params[:action] == "polling") ||
             (params[:controller] == "users" && (params[:action] == "join_accounts" || params[:action] == "confirm_credentials")))
      session[:proposal_id] = nil
      session[:proposal_comment] = nil
      session[:user_return_to] = request.url
      end
      # If devise model is not User, then replace :user_return_to with :{your devise model}_return_to
  end
  
  
  def post_contribute
    ProposalComment.transaction do
      @proposal_comment =  @proposal.comments.build(params[:proposal_comment])
      @proposal_comment.user_id = current_user.id
      @proposal_comment.request = request
      @proposal_comment.save!
      @ranking = ProposalCommentRanking.new
      @ranking.user_id = current_user.id
      @ranking.proposal_comment_id = @proposal_comment.id
      @ranking.ranking_type_id = RankingType::POSITIVE
      @ranking.save!
      
      generate_nickname(current_user,@proposal)
      
      #notifica solo se si tratta di un nuovo contributo      
      notify_user_comment_proposal(@proposal_comment) unless @proposal_comment.parent_proposal_comment_id
      flash[:notice] = 'Contributo inserito correttamente.'
    end
  end
  
  def generate_nickname(user,proposal)
    nickname = ProposalNickname.find_by_user_id_and_proposal_id(user.id,proposal.id)
    if !nickname
      loop = true
      while loop do
        nickname = NicknameGeneratorHelper.give_me_a_nickname
        loop = ProposalNickname.find_by_proposal_id_and_nickname(proposal.id,nickname)
      end
      ProposalNickname.create(:user_id => user.id, :proposal_id => proposal.id, :nickname => nickname)
    end
  end
  
  
  #redirect all'ultima pagina in cui ero
  def after_sign_in_path_for(resource)
    #se in sessione ho memorizzato un contributo, inseriscilo e mandami alla pagina della proposta
    if session[:proposal_comment] && session[:proposal_id]
      @proposal = Proposal.find(session[:proposal_id])
      params[:proposal_comment] = session[:proposal_comment]
      session[:proposal_id] = nil
      session[:proposal_comment] = nil
      post_contribute rescue nil
      proposal_path(@proposal)
    else
      env = request.env
      ret = env['omniauth.origin'] || stored_location_for(resource) || root_path
      ret
    end
  end
  
  #redirect alla pagina delle proposte
  def after_sign_up_path_for(resource)
    return proposals_path
  end

  protected
  def discard_flash_if_xhr
    flash.discard if request.xhr?
  end
  
  unless Rails.application.config.consider_all_requests_local
    rescue_from Exception, :with => :render_error
    rescue_from ActiveRecord::RecordNotFound, :with => :render_404
    rescue_from ActionController::RoutingError, :with => :render_404
    rescue_from ActionController::UnknownController, :with => :render_404
    rescue_from ActionController::UnknownAction, :with => :render_404
  end 
  
  rescue_from CanCan::AccessDenied do |exception|
    permissions_denied
  end
  
  
  private
  
  def prepare_for_mobile
    session[:mobile_param] = params[:mobile] if params[:mobile]
    request.format = :mobile if false#mobile_device?
  end
  
  def mobile_device?
    if session[:mobile_param]
      session[:mobile_param] == "1"
    else
      request.user_agent =~ /Mobile|webOS/
    end
  end

end
