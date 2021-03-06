class ProposalComment < ActiveRecord::Base
  include BlogKitModelHelper
  include LogicalDeleteHelper

  belongs_to :user, :class_name => 'User', :foreign_key => :user_id
  belongs_to :contribute, :class_name => 'ProposalComment', :foreign_key => :parent_proposal_comment_id
  has_many :replies, :class_name => 'ProposalComment', :foreign_key => :parent_proposal_comment_id, dependent: :destroy
  belongs_to :proposal, :class_name => 'Proposal', :foreign_key => :proposal_id, :counter_cache => true
  has_many :rankings, :class_name => 'ProposalCommentRanking', :dependent => :destroy
  belongs_to :paragraph

  has_many :integrated_contributes, :class_name => 'IntegratedContribute', dependent: :destroy
  has_many :proposal_revisions, :class_name => 'ProposalRevision', :through => :integrated_contributes

  has_many :reports, :class_name => 'ProposalCommentReport', :foreign_key => :proposal_comment_id

  validates_length_of :content, :minimum => 10, :maximum => CONTRIBUTE_MAX_LENGTH
  
  attr_accessor :collapsed
  
  after_initialize :set_collapsed
  
  validate :check_last_comment

  scope :contributes, {:conditions => ['parent_proposal_comment_id is null']}

  scope :unintegrated, {:conditions => {:integrated => false}}

  scope :noise, {:conditions => {:noise => true}}

  scope :listable, {:conditions => {:integrated => false, :noise => false}}



  attr_accessor :section_id

  before_create :set_paragraph_id

  def set_paragraph_id
    self.paragraph = Paragraph.first(:conditions => {:section_id => self.section_id}, :select => :id)

  end
  
  def set_collapsed     
     @collapsed = false     
  end
 
  def check_last_comment
    comments =  self.proposal.comments.find_all_by_user_id(self.user_id, :order => "created_at DESC")
    comment = comments.first
    if LIMIT_COMMENTS and comment and ((Time.now - comment.created_at) < 30.seconds)
       self.errors.add(:created_at,"devono passare almeno trenta secondi tra un commento e l'altro.")
    end
  end

  # Used to set more tracking for akismet
  def request=(request)
    self.user_ip    = request.remote_ip
    self.user_agent = request.env['HTTP_USER_AGENT']
    self.referrer   = request.env['HTTP_REFERER']
  end
 
end
