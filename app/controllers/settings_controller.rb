class SettingsController < ApplicationController
  def show
  end

  def update
    if current_user.update(settings_params)
      respond_to do |format|
        format.html { redirect_to settings_path, notice: "Saved." }
        format.json { head :ok }
      end
    else
      respond_to do |format|
        format.html { render :show, status: :unprocessable_entity }
        format.json { render json: { errors: current_user.errors }, status: :unprocessable_entity }
      end
    end
  end

  private

  def settings_params
    params.require(:user).permit(:name, :stamp_choice, :timezone, :work_hours_target, :sundown_time, :theme)
  end
end
