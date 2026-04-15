class SettingsController < ApplicationController
  def show
    load_hey_calendars
  end

  def update
    if current_user.update(settings_params)
      redirect_to settings_path, notice: "Saved."
    else
      load_hey_calendars
      flash.now[:alert] = current_user.errors.full_messages.to_sentence
      render :show, status: :unprocessable_entity
    end
  end

  private

  def load_hey_calendars
    @hey_calendars = []
    return unless current_user.hey_connected?
    begin
      data = HeyClient.new(current_user).calendars
      @hey_calendars = data if data.is_a?(Array)
    rescue HeyClient::AuthError
      @hey_calendars = []
    end
  end

  def settings_params
    params.require(:user).permit(
      :name, :stamp_choice, :timezone, :work_hours_target, :sundown_time, :theme,
      :hey_default_calendar_id
    )
  end
end
