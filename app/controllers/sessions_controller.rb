class SessionsController < ApplicationController
  def new
    session[:redirect_to] ||= request.referrer
    redirect_to client.auth_code.authorize_url(redirect_uri: login_complete_url), allow_other_host: true
  end

  def complete
    if params.has_key?(:code)
      token = client.auth_code.get_token(params[:code], redirect_uri: login_complete_url)
      user_data = JSON.parse(token.get("/api/v1/people/me_community?secret_token=#{HackerSchool.secret_token}").body)

      user = AccountImporter.new(user_data).import

      login(user)

      if session[:redirect_to]
        redirect_to session.delete(:redirect_to)
      else
        redirect_to root_url
      end
    else
      render plain: "Invalid", status: :unprocessable_entity
    end
  end

  def destroy
    logout
    render layout: "application", html: "<p>Logged out.</p>".html_safe
  end

private
  def client
    @client ||= HackerSchool.new.client
  end
end
