class Ability
  include CanCan::Ability

  def initialize(user)
    @user = user

    return if user.deactivated?

    can :me, User

    can :read, SubforumGroup

    can :read, Subforum, required_role: {users: user}

    alias_action :subscribe, :unsubscribe, to: :read
    can [:create, :read], DiscussionThread, subforum: {required_role: {users: user}}

    if user.is_admin?
      can [:pin, :unpin], DiscussionThread
    end

    can [:create, :update], Subscription, user: user

    can [:create, :read], Post, thread: {subforum: {required_role: {users: user}}}
    can :update, Post, author: user

    alias_action :read, to: :update
    can :update, Notification, user: user
  end

  # def can?(action, resource)
  #   if resource.respond_to?(:required_roles)
  #     @user.satisfies_roles?(*resource.required_roles) && super
  #   else
  #     super
  #   end
  # end
end
