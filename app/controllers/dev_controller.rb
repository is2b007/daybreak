class DevController < ApplicationController
  skip_before_action :authenticate_user!
  skip_before_action :require_onboarding!

  def login
    user = User.find(params[:user_id])
    session[:user_id] = user.id
    redirect_to root_path
  end

end
