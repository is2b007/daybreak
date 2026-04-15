class SyncController < ApplicationController
  def basecamp
    SyncBasecampAssignmentsJob.perform_now(current_user.id)
    SyncCalendarEventsJob.perform_later(current_user.id)
    respond_to do |format|
      format.html { redirect_back_or_to root_path, notice: "Basecamp tasks updated." }
      format.json { head :ok }
    end
  rescue StandardError => e
    Rails.logger.error("SyncController#basecamp failed: #{e.class}: #{e.message}")
    respond_to do |format|
      format.html { redirect_back_or_to root_path, alert: "Could not sync with Basecamp. Try again in a moment." }
      format.json { head :internal_server_error }
    end
  end

  def hey
    unless current_user.hey_connected?
      respond_to do |format|
        format.html { redirect_back_or_to root_path, alert: "Connect HEY in Settings to sync." }
        format.json { head :unprocessable_entity }
      end
      return
    end

    SyncHeyEmailsJob.perform_now(current_user.id)
    respond_to do |format|
      format.html { redirect_back_or_to root_path, notice: "HEY inbox updated." }
      format.json { head :ok }
    end
  rescue StandardError => e
    Rails.logger.error("SyncController#hey failed: #{e.class}: #{e.message}")
    respond_to do |format|
      format.html { redirect_back_or_to root_path, alert: "Could not sync HEY. Try again in a moment." }
      format.json { head :internal_server_error }
    end
  end

  def basecamp_more
    offset = [ params[:offset].to_i, 0 ].max
    limit  = 20
    scope  = current_user.task_assignments.basecamp.incomplete
               .where(week_bucket: "inbox").ordered
    chunk  = scope.offset(offset).limit(limit + 1)
    has_more = chunk.size > limit
    tasks = chunk.first(limit)
    html = render_to_string(
      partial: "layouts/bc_inbox_items",
      locals: { tasks: tasks },
      layout: false,
      formats: [ :html ]
    )
    render json: { html: html, next_offset: offset + tasks.size, has_more: has_more }
  end
end
