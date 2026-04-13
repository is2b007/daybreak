class HeyEmailsController < ApplicationController
  before_action :set_email, except: [ :more ]

  # GET /hey_emails/more?offset=75 — JSON fragment for infinite scroll in the HEY panel.
  def more
    offset = [ params[:offset].to_i, 0 ].max
    limit  = 25
    folder = params[:folder].to_s
    label  = params[:label].to_s
    base_scope = current_user.hey_emails.active.ordered
    base_scope = base_scope.where(folder: folder) if folder.present? && HeyEmail.folders.key?(folder)
    base_scope = base_scope.where(label: label) if label.present?

    if !Rails.env.test? && current_user.hey_connected? && offset.zero?
      cache_key = "hey_sync_enqueued:#{current_user.id}:#{folder.presence || 'all'}"
      unless Rails.cache.exist?(cache_key)
        Rails.cache.write(cache_key, true, expires_in: 30.seconds)
        SyncHeyEmailsJob.perform_later(current_user.id, folder: folder.presence)
      end
    end
    chunk  = base_scope.offset(offset).limit(limit + 1)
    has_more = chunk.size > limit
    emails = chunk.first(limit)
    html = render_to_string(
      partial: "layouts/hey_inbox_items",
      locals: { emails: emails },
      layout: false,
      formats: [ :html ]
    )
    render json: {
      html: html,
      next_offset: offset + emails.size,
      has_more: has_more
    }
  end

  def triage
    week_start = Date.current.in_time_zone(current_user.timezone).beginning_of_week(:monday)

    ActiveRecord::Base.transaction do
      current_user.task_assignments.create!(
        source: :local,
        title: @email.subject,
        week_start_date: week_start,
        week_bucket: "sometime",
        size: :medium,
        status: :pending
      )
      @email.triage!
    end

    respond_removed("Added to this week.")
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotFound => e
    Rails.logger.warn("Triage action failed: #{e.message}")
    render json: { error: "Could not save. Try again?" }, status: :unprocessable_entity
  end

  def dismiss
    @email.dismiss!
    respond_removed("Dismissed.")
  end

  # POST /hey_emails/:id/plan
  # Promotes a HEY inbox row into a real TaskAssignment via drag-and-drop.
  # Mirrors TaskAssignmentsController#move stream patterns so the board updates identically.
  def plan
    week_start = Date.current.beginning_of_week(:monday)
    day_ctx    = day_view_stream_context?

    task = ActiveRecord::Base.transaction do
      if params[:target_bucket] == "sometime"
        t = current_user.task_assignments.create!(
          source: :local,
          title: @email.subject,
          description: @email.snippet.presence,
          hey_app_url: @email.hey_url,
          week_start_date: week_start,
          week_bucket: "sometime",
          size: :medium,
          status: :pending,
          position: params[:position].to_i
        )
      else
        target_date = Date.parse(params[:target_date])
        target_plan = current_user.day_plans.find_or_create_by!(date: target_date)
        t = current_user.task_assignments.create!(
          source: :local,
          title: @email.subject,
          description: @email.snippet.presence,
          hey_app_url: @email.hey_url,
          day_plan: target_plan,
          week_start_date: target_date.beginning_of_week(:monday),
          week_bucket: "day",
          size: :medium,
          status: :pending,
          position: params[:position].to_i
        )
      end
      @email.triage!
      t
    end

    respond_to do |format|
      format.turbo_stream do
        streams = [ turbo_stream.remove("hey_email_#{@email.id}") ]

        if params[:target_bucket] == "sometime"
          unless day_ctx
            sometime_tasks = current_user.task_assignments
              .where(week_bucket: "sometime", week_start_date: week_start)
              .ordered
            streams << turbo_stream.replace("sometime_row",
              partial: "weeks/sometime_row",
              locals: { tasks: sometime_tasks })
          end
        else
          target_date = task.day_plan.date

          if day_ctx
            streams << stream_replace_day_plan_tasks(target_date)
          else
            streams << turbo_stream.replace("day_#{target_date}",
              partial: "weeks/day_column",
              locals: {
                date: target_date,
                tasks: current_user.task_assignments
                         .for_week(target_date.beginning_of_week(:monday))
                         .where(day_plan: task.day_plan)
                         .ordered,
                events: []
              })
          end
        end

        render turbo_stream: streams
      end
      format.html { redirect_to root_path, notice: "Added to your plan." }
    end
  rescue ArgumentError, ActiveRecord::RecordInvalid => e
    Rails.logger.warn("HEY email plan failed: #{e.message}")
    render json: { error: "Could not add to plan. Try again?" }, status: :unprocessable_entity
  end

  private

  def set_email
    @email = current_user.hey_emails.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    # Sync race: the row was pruned between render and click. The row is gone
    # from the DB, so sweep it out of the UI too — don't leave a ghost button.
    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream.remove("hey_email_#{params[:id]}") }
      format.html { redirect_to root_path, notice: "Already handled." }
    end
  end

  def respond_removed(notice)
    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream.remove("hey_email_#{@email.id}") }
      format.html { redirect_to root_path, notice: notice }
    end
  end

  def day_view_stream_context?
    return true if params[:view].to_s == "day"
    ref = request.referer.to_s
    return false if ref.blank?
    URI.parse(ref).path.match?(%r{/days/\d{4}-\d{2}-\d{2}})
  rescue URI::InvalidURIError
    false
  end

  def stream_replace_day_plan_tasks(date)
    plan  = current_user.day_plans.find_by(date: date)
    tasks = plan ? current_user.task_assignments.where(day_plan: plan).ordered : TaskAssignment.none
    turbo_stream.replace(
      "day_plan_tasks_#{date}",
      partial: "days/day_plan_tasks",
      locals: { date: date, tasks: tasks }
    )
  end
end
