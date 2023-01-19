class ApplicationController < ActionController::Base
  include CurrentUser

  def login(user)
    session[:user_id] = user.id
  end

  def logout
    reset_session
  end

  def require_login
    unless current_user
      session[:redirect_to] = request.url
      redirect_to login_url
    end
  end

  def require_admin
    if !current_user || !current_user.is_admin?
      redirect_to root_path
    end
  end
end
