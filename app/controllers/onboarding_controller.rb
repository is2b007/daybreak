class OnboardingController < ApplicationController
  skip_before_action :require_onboarding!
  before_action :redirect_if_onboarded, except: [ :restart ]

  STEPS = 7

  def show
    @step = (params[:step] || 1).to_i.clamp(1, STEPS)
  end

  def update
    @step = params[:step].to_i

    case @step
    when 1
      # welcome — nothing to persist
      redirect_to onboarding_path(step: 2)
    when 2
      current_user.update!(name: params[:name]) if params[:name].present?
      redirect_to onboarding_path(step: 3)
    when 3
      current_user.update!(stamp_choice: params[:stamp_choice]) if params[:stamp_choice].present?
      redirect_to onboarding_path(step: 4)
    when 4
      # basecamp — already connected (that's how they got here via OAuth).
      # Trigger a visible sync so the inbox starts filling while they continue.
      SyncBasecampAssignmentsJob.perform_later(current_user.id)
      redirect_to onboarding_path(step: 5)
    when 5
      if params[:connect_hey] == "true"
        redirect_to auth_hey_path
      else
        redirect_to onboarding_path(step: 6)
      end
    when 6
      current_user.update!(timezone: params[:timezone]) if params[:timezone].present?
      redirect_to onboarding_path(step: 7)
    when 7
      complete
    end
  end

  def complete
    current_user.update!(onboarded: true)
    redirect_to root_path, notice: "Glad you're here, #{current_user.greeting_name}."
  end

  def restart
    current_user.update!(onboarded: false)
    redirect_to onboarding_path(step: 1)
  end

  private

  def redirect_if_onboarded
    redirect_to root_path if current_user.onboarded?
  end
end
