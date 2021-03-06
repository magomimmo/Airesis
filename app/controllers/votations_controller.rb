#encoding: utf-8
class VotationsController < ApplicationController

  layout 'open_space'

  before_filter :authenticate_user!

  before_filter :load_proposals, :only => [ :show]

  
  def show
    @page_title = "Sezione votazioni"
  end

  def vote
    Proposal.transaction do
      @proposal = Proposal.find_by_id(params[:proposal_id])

      authorize! :vote, @proposal

      vote = UserVote.new(:user_id => current_user.id, :proposal_id => @proposal.id)
      vote.vote_type_id = params[:vote_type].to_i unless @proposal.secret_vote
      vote.save!

      if params[:vote_type] == POSITIVE_VOTE.to_s
        @proposal.vote.positive += 1
      elsif params[:vote_type] == NEUTRAL_VOTE.to_s
        @proposal.vote.neutral += 1
      elsif params[:vote_type] == NEGATIVE_VOTE.to_s
        @proposal.vote.negative += 1
      end
      @proposal.vote.save!

      load_proposals
      respond_to do |format|
        flash[:notice] = 'Voto registrato'
        format.js   { render :update do |page|
            page.replace_html "flash_messages", :partial => 'layouts/flash', :locals => {:flash => flash}
            page.replace_html "vote_panel_container", :partial => "proposals/vote_panel", :locals =>  {:proposals => @proposals}
          end
        }
        format.html { redirect_to votation_path }
      end
  end
  rescue ActiveRecord::ActiveRecordError => e
    if @proposal.errors[:user_votes]
      respond_to do |format|
        load_proposals
        flash[:error] = 'Hai già votato per questa proposta'
        format.js   { render :update do |page|
            page.replace_html "flash_messages", :partial => 'layouts/flash', :locals => {:flash => flash}
            page.replace_html "proposals_list", :partial => "votations/list", :locals =>  {:proposals => @proposals}
          end
        }
        format.html { redirect_to votation_path }
      end
    end
  end

  #un utente invia il voto in formato schulze
  def vote_schulze
    begin
      Proposal.transaction do
        @proposal = Proposal.find_by_id(params[:proposal_id])
        votestring = params[:data][:votes]
        solutions = votestring.split(/;|,/).map{|a| a.to_i}.sort #lista degli id delle soluzioni
        p_sol = @proposal.solutions.pluck(:id).sort
        raise Exception unless (p_sol <=> solutions) == 0 #se c'è discrepanza tra gli id delle soluzioni e quelli inviati dal client solleva un'eccezione

        #salva la votazione dell'utente
        schulz = @proposal.schulze_votes.find_or_create_by_preferences(votestring)
        schulz.count += 1
        schulz.save!

        #memorizza che l'utente ha effettuato la votazione
        vote = UserVote.new(:user_id => current_user.id, :proposal_id => @proposal.id)
        vote.vote_schulze = votestring unless @proposal.secret_vote
        vote.save!
      end
      respond_to do |format|
        flash[:notice] = "Voto inviato correttamente!"
        format.html { render :action => "show" }
        format.js {
          render :update do |page|
            page.replace_html "flash_messages", :partial => 'layouts/flash', :locals => {:flash => flash}
          end
        }
      end

    rescue Exception => e
      respond_to do |format|
        #magari ha provato a votare due volte!
        flash[:error] = "Errore durante l'inserimento del tuo voto. Spiacenti."
        format.html { redirect_to @proposal }
        format.js {
          render :update do |page|
            page.replace_html "flash_messages", :partial => 'layouts/flash', :locals => {:flash => flash}
          end
        }
      end
    end
  end



  protected

  #carica le proposte per le quali può votare l'utente connesso
  def load_proposals
    #la proposta deve essere in stato 'in votazione'
    #l'utente non deve avere già votato per questa proposta
    #la proposta deve essere pubblica
    #se la proposta è privata deve avere i permessi per votare in quel gruppo

    #estrai tutte le proposte in votazione che non ho ancora votato
    @proposals_tmp = Proposal.includes({:category => :translations}, :vote_period, {:users => :image}).all(:select => "p.*",:joins=>"p", :include => [:presentation_groups, :quorum], :conditions => "p.proposal_state_id = 4 and p.id not in (select proposal_id from user_votes where user_id = "+current_user.id.to_s+" and proposal_id = p.id)")
    @proposals = []
    @proposals_tmp.each do |proposal|
        @proposals << proposal if can? :vote, proposal
    end
  end
end  
