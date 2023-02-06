require 'open-uri'
require 'json'
require 'set'

class AccountImporter
  class ImportError < StandardError; end

  def self.import_all
    URI.open("#{HackerSchool.site}/api/v1/people?secret_token=#{HackerSchool.secret_token}&only_ids=true") do |f|
      id_pages = JSON.parse(f.read).each_slice(100)

      id_pages.each do |ids|
        delay.import(ids)
      end
    end
  end

  def self.import(ids)
    URI.open("#{HackerSchool.site}/api/v1/people?secret_token=#{HackerSchool.secret_token}&ids=#{ids.to_json}") do |f|
      JSON.parse(f.read).each do |user_data|
        new(user_data).import
      end
    end
  end

  def self.sync_deactivated_accounts
    URI.open("#{HackerSchool.site}/api/v1/people/deactivated?secret_token=#{HackerSchool.secret_token}") do |f|
      deactivated_ids = JSON.parse(f.read)
      User.where(deactivated: false, hacker_school_id: deactivated_ids).each do |user|
        user.deactivate
      end
    end
  end

  attr_reader :user, :user_data
  private :user, :user_data

  def initialize(user_data)
    @user_data = user_data
    @user = User.where(hacker_school_id: user_data["id"]).first_or_initialize
  end

  def import
    User.transaction do
      set_or_update_user_data
      autosubscribe_to_subforums
    end

    user
  end

  private

  def set_or_update_user_data
    # We assume only active users will hit this method, so this
    # handles reactivating an account if necessary
    user.deactivated = false
    user.hacker_school_id = user_data["id"]
    user.first_name = user_data["first_name"]
    user.last_name = user_data["last_name"]
    user.email = user_data["email"]
    user.avatar_url = user_data["image"] if user_data["has_photo"]
    user.batch_name = user_data["community_affiliation"]
    user.groups = get_groups
    user.roles = get_roles

    # The welcome message doesn't make sense for RC start participants. Hide it.
    if rc_start_participant?
      user.last_read_welcome_message_at = Time.zone.now
    end

    user.save!
  end

  def autosubscribe_to_subforums
    names = autosubscribe_subforum_names

    subforums = Subforum.where(name: names)

    # Use subforums.length to force the query for the actual data instead of
    # the count so we don't trigger a second query when we call subforums.each
    unless subforums.length == names.size
      raise ImportError, "Got a different number of subforums (#{subforums.length}) than we had subforum names (#{names.size})."
    end

    subforums.each do |subforum|
      user.subscribe_to_unless_existing(subforum, "You are receiving emails because you were auto-subscribed when your account was imported from recurse.com.")
    end
  end

  def get_groups
    groups = Set.new
    groups << Group.everyone

    user_data["batches"].each do |batch|
      groups << Group.for_batch_api_data(batch)
    end

    if rc_start_participant?
      groups << Group.rc_start
    end

    if currently_at_hacker_school?
      groups << Group.current_hacker_schoolers
    else
      groups -= [Group.current_hacker_schoolers]
    end

    if faculty?
      groups << Group.faculty
    else
      groups -= [Group.faculty]
    end

    groups.to_a
  end

  def get_roles
    roles = Set.new

    if !rc_start_participant?
      roles << Role.pre_batch
    end

    if rc_start_participant? || full_hacker_schooler?
      roles << Role.rc_start
    end

    roles << Role.full_hacker_schooler if full_hacker_schooler?

    if faculty?
      roles |= [Role.pre_batch, Role.rc_start, Role.full_hacker_schooler, Role.admin]
    end

    roles.to_a
  end

  def autosubscribe_subforum_names
    names = []

    # currently_at_hacker_school? includes residents. hacker_schooler? does not.
    names += ["Welcome", "Housing"] if hacker_schooler? && batch_in_the_future?
    names += ["New York", "397 Bridge"] if currently_at_hacker_school?
    names += ["General"] if currently_at_hacker_school? && should_subscribe_to_general?
    names += ["RC Start"] if rc_start_participant? || active_rc_start_mentor?

    names
  end

  GENERAL_SUBFORUM_SUBSCRIPTION_CUTOFF = Date.parse("December 3, 2015")

  def should_subscribe_to_general?
    user.created_at >= GENERAL_SUBFORUM_SUBSCRIPTION_CUTOFF
  end

  def batch_in_the_future?
    !full_hacker_schooler?
  end

  def full_hacker_schooler?
    stint_started = user_data["stints"].any? do |stint|
      stint["type"] == "residency" || stint["type"] == "retreat" && (Date.parse(stint["start_date"]) - 1.day).past?
    end

    stint_started || user_data["batch"] && (Date.parse(user_data["batch"]["start_date"]) - 1.day).past?
  end

  def rc_start_participant?
    user_data["is_rc_start_participant"]
  end

  def faculty?
    user_data["is_faculty"]
  end

  def hacker_schooler?
    user_data["is_hacker_schooler"]
  end

  def currently_at_hacker_school?
    user_data["currently_at_hacker_school"]
  end

  def active_rc_start_mentor?
    user_data["active_rc_start_mentor"]
  end
end
