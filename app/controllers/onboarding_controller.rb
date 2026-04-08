class OnboardingController < ApplicationController
  skip_before_action :require_onboarding!
  before_action :redirect_if_onboarded

  def show
    @step = (params[:step] || 1).to_i.clamp(1, 4)
  end

  def update
    @step = params[:step].to_i

    case @step
    when 1
      current_user.update!(name: params[:name]) if params[:name].present?
      redirect_to onboarding_path(step: 2)
    when 2
      current_user.update!(stamp_choice: params[:stamp_choice]) if params[:stamp_choice].present?
      redirect_to onboarding_path(step: 3)
    when 3
      if params[:connect_hey] == "true"
        redirect_to auth_hey_path
      else
        redirect_to onboarding_path(step: 4)
      end
    when 4
      current_user.update!(timezone: params[:timezone]) if params[:timezone].present?
      complete
    end
  end

  def complete
    current_user.update!(onboarded: true)
    redirect_to root_path, notice: "Glad you're here, #{current_user.greeting_name}."
  end

  private

  def redirect_if_onboarded
    redirect_to root_path if current_user.onboarded?
  end
end
