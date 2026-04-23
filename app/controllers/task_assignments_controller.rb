class TaskAssignmentsController < ApplicationController
  before_action :set_task, only: [ :show, :focus, :update, :destroy, :move, :cycle_size, :complete, :defer, :timebox, :comment, :restore_hey_email ]

  def show
    @bc_comments = []
    @bc_comments_error = nil
    @hey_email_body = nil
    if @task.basecamp? && @task.basecamp_bucket_id.present? && @task.external_id.present?
      begin
        client = BasecampClient.new(current_user)
        @bc_comments = Array(client.comments(@task.basecamp_bucket_id, @task.external_id))
      rescue BasecampClient::AuthError
        @bc_comments_error = "Your Basecamp session looks expired."
      rescue BasecampClient::RateLimitError
        @bc_comments_error = "Basecamp is throttling — try again in a moment."
      rescue StandardError => e
        Rails.logger.warn("Basecamp comments fetch failed: #{e.class}: #{e.message}")
        @bc_comments_error = "Couldn't reach Basecamp for comments."
      end
    end
    if @task.hey_app_url.present?
      @hey_email_body = current_user.hey_emails.find_by(hey_url: @task.hey_app_url)&.snippet
    end

    respond_to do |format|
      format.turbo_stream { render :show }
      format.html { render :show }
    end
  end

  def focus
    @active_timer = current_user.local_timer_sessions.running.find_by(task_assignment: @task)
    @any_running_timer = current_user.local_timer_sessions.running.first

    # Basecamp: pull the full todo (for its description/content) and the
    # comments thread so the focus view can show both alongside your notes.
    @bc_todo = nil
    @bc_comments = []
    @bc_comments_error = nil
    if @task.basecamp? && @task.basecamp_bucket_id.present? && @task.external_id.present?
      begin
        client = BasecampClient.new(current_user)
        @bc_todo = client.todo(@task.external_id)
        @bc_comments = Array(client.comments(@task.basecamp_bucket_id, @task.external_id))
      rescue BasecampClient::AuthError
        @bc_comments_error = "Your Basecamp session looks expired."
      rescue BasecampClient::RateLimitError
        @bc_comments_error = "Basecamp is throttling — try again in a moment."
      rescue StandardError => e
        Rails.logger.warn("Basecamp focus fetch failed: #{e.class}: #{e.message}")
        @bc_comments_error = "Couldn't reach Basecamp."
      end
    end

    # HEY: email body is mirrored into hey_emails at sync time; no live fetch.
    @hey_email_body = nil
    if @task.hey_app_url.present?
      @hey_email_body = current_user.hey_emails.find_by(hey_url: @task.hey_app_url)&.snippet
    end

    respond_to do |format|
      format.turbo_stream { render :focus }
      format.html { render :focus }
    end
  end

  def create
    day_plan = current_user.day_plans.find_or_create_by!(date: params[:date])
    @task = current_user.task_assignments.create!(
      day_plan: day_plan,
      title: params[:title],
      size: params[:size] || :medium,
      planned_duration_minutes: params[:planned_duration_minutes],
      source: :local,
      week_start_date: day_plan.date.beginning_of_week(:monday),
      week_bucket: "day",
      position: day_plan.task_assignments.count
    )

    respond_to do |format|
      format.turbo_stream do
        date = day_plan.date
        tasks = current_user.task_assignments
          .includes(:day_plan).left_joins(:day_plan)
          .where(day_plans: { date: date }).for_day.ordered
        events = current_user.calendar_events
          .pinned_to_week_board
          .where(starts_at: date.beginning_of_day..date.end_of_day)
          .chronological
          .group_by { |e| e.all_day ? e.starts_at.utc.to_date : e.starts_at.in_time_zone(current_user.timezone).to_date }
          .transform_values { |evs| evs.map(&:to_view_hash) }
        render turbo_stream: turbo_stream.replace(
          "day_#{date}",
          partial: "weeks/day_column",
          locals: { date: date, tasks: tasks, events: events[date] || [] }
        )
      end
      format.html { redirect_back fallback_location: root_path }
    end
  end

  def update
    permitted = task_params
    permitted = permitted.except(:title) if @task.hey_app_url.present?
    @task.update!(permitted)
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace("task_#{@task.id}", partial: "shared/task_card", locals: { task: @task, compact: true })
      end
      format.html { redirect_back fallback_location: root_path }
    end
  end

  def destroy
    plan_date = @task.day_plan&.date
    week_start = Date.current.beginning_of_week(:monday)
    was_sometime = @task.week_bucket == "sometime"
    day_ctx = day_view_stream_context?
    had_timebox = @task.timeboxed?

    @task.destroy!
    respond_to do |format|
      format.turbo_stream do
        streams = [ turbo_stream.remove("task_#{@task.id}") ]

        if plan_date
          if day_ctx
            streams << stream_replace_day_plan_tasks(plan_date)
            streams << stream_replace_day_timeline(plan_date) if had_timebox
          else
            plan = current_user.day_plans.find_by(date: plan_date)
            streams << turbo_stream.replace("day_#{plan_date}",
              partial: "weeks/day_column",
              locals: {
                date: plan_date,
                tasks: current_user.task_assignments
                         .for_week(plan_date.beginning_of_week(:monday))
                         .where(day_plan: plan)
                         .ordered,
                events: day_column_calendar_events_for(current_user, plan_date)
              })
          end
        elsif was_sometime
          streams << turbo_stream.replace("sometime_row",
            partial: "weeks/sometime_row",
            locals: { tasks: current_user.task_assignments
              .where(week_bucket: "sometime", week_start_date: week_start).ordered })
        end

        render turbo_stream: streams
      end
      format.html { redirect_back fallback_location: root_path }
    end
  end

  def move
    from_inbox = params[:from_inbox] == "1"
    week_start = Date.current.beginning_of_week(:monday)
    day_ctx = day_view_stream_context?

    if params[:target_bucket] == "inbox"
      previous_date = @task.day_plan&.date
      source_date = params[:source_date].present? ? Date.parse(params[:source_date]) : nil
      clear_hey_mirrored_todo_if_present!
      @task.update!(day_plan: nil, week_start_date: nil, week_bucket: "inbox", position: 0, hey_mirrored_todo_id: nil)

      respond_to do |format|
        format.turbo_stream do
          streams = [ turbo_stream.remove("task_#{@task.id}") ]

          if day_ctx
            refresh_date = source_date || previous_date
            streams << stream_replace_day_plan_tasks(refresh_date) if refresh_date
          else
            if source_date
              source_plan = current_user.day_plans.find_by(date: source_date)
              streams << turbo_stream.replace("day_#{source_date}",
                partial: "weeks/day_column",
                locals: {
                  date: source_date,
                  tasks: current_user.task_assignments
                           .for_week(source_date.beginning_of_week(:monday))
                           .where(day_plan: source_plan)
                           .ordered,
                  events: day_column_calendar_events_for(current_user, source_date)
                })
            end

            streams << turbo_stream.replace("sometime_row",
              partial: "weeks/sometime_row",
              locals: { tasks: current_user.task_assignments
                .where(week_bucket: "sometime", week_start_date: week_start).ordered })
          end

          streams << turbo_stream.prepend("bc-inbox-list",
            partial: "layouts/inbox_item",
            locals: { task: @task })

          render turbo_stream: streams
        end
        format.html { redirect_back fallback_location: root_path }
      end

    elsif params[:target_bucket] == "sometime"
      @task.update!(
        day_plan: nil,
        week_start_date: week_start,
        week_bucket: "sometime",
        position: params[:position].to_i
      )

      sync_enqueued = current_user.hey_connected? && !Rails.env.test?
      if sync_enqueued
        SyncSometimeTodoToHeyJob.perform_later(@task.id)
      end

      sometime_tasks = current_user.task_assignments
        .where(week_bucket: "sometime", week_start_date: week_start)
        .ordered

      respond_to do |format|
        format.turbo_stream do
          streams = []
          streams << turbo_stream.replace("sometime_row",
            partial: "weeks/sometime_row",
            locals: { tasks: sometime_tasks }) unless day_ctx
          streams << turbo_stream.remove("inbox_task_#{@task.id}") if from_inbox
          render turbo_stream: streams
        end
        format.html { redirect_back fallback_location: root_path }
      end
    else
      target_date = Date.parse(params[:target_date])
      target_plan = current_user.day_plans.find_or_create_by!(date: target_date)

      clear_hey_mirrored_todo_if_present! if @task.week_bucket == "sometime"

      @task.update!(
        day_plan: target_plan,
        week_start_date: target_date.beginning_of_week(:monday),
        week_bucket: "day",
        position: params[:position].to_i,
        hey_mirrored_todo_id: nil
      )

      respond_to do |format|
        format.turbo_stream do
          streams = []

          if day_ctx
            streams << turbo_stream.remove("inbox_task_#{@task.id}") if from_inbox
            streams << stream_replace_day_plan_tasks(target_date)
            streams << stream_replace_day_timeline(target_date)

            if params[:source_date].present?
              source_date = Date.parse(params[:source_date])
              if source_date != target_date
                streams << stream_replace_day_plan_tasks(source_date)
                streams << stream_replace_day_timeline(source_date)
              end
            end
          else
            streams << turbo_stream.replace("day_#{target_date}",
              partial: "weeks/day_column",
              locals: {
                date: target_date,
                tasks: current_user.task_assignments
                         .for_week(target_date.beginning_of_week(:monday))
                         .where(day_plan: target_plan)
                         .ordered,
                events: day_column_calendar_events_for(current_user, target_date)
              })

            if params[:source_date].present?
              source_date = Date.parse(params[:source_date])
              if source_date != target_date
                source_plan = current_user.day_plans.find_by(date: source_date)
                streams << turbo_stream.replace("day_#{source_date}",
                  partial: "weeks/day_column",
                  locals: {
                    date: source_date,
                    tasks: current_user.task_assignments
                             .for_week(source_date.beginning_of_week(:monday))
                             .where(day_plan: source_plan)
                             .ordered,
                    events: day_column_calendar_events_for(current_user, source_date)
                  })
              end
            end

            streams << turbo_stream.remove("inbox_task_#{@task.id}") if from_inbox
          end

          render turbo_stream: streams
        end
        format.html { redirect_back fallback_location: root_path }
      end
    end
  end

  def cycle_size
    @task.cycle_size!
    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream.replace("task_#{@task.id}", partial: "shared/task_card", locals: { task: @task, compact: true }) }
      format.html { redirect_back fallback_location: root_path }
    end
  end

  def complete
    rotation = params[:rotation]&.to_i
    plan = @task.day_plan
    @task.complete!(rotation: rotation)
    WriteCompletionJob.perform_later(@task.id) if @task.basecamp? || @task.hey? || @task.hey_mirrored_todo_id.present?

    respond_to do |format|
      format.turbo_stream do
        streams = [
          turbo_stream.remove("task_#{@task.id}"),
          turbo_stream.append("day_#{plan&.date}_completed",
            partial: "shared/task_card",
            locals: { task: @task, compact: true })
        ]
        if plan
          tasks = current_user.task_assignments.where(day_plan: plan).ordered
          streams << turbo_stream.replace(
            "day_plan_tasks_#{plan.date}",
            partial: "days/day_plan_tasks",
            locals: { date: plan.date, tasks: tasks }
          )
          streams << stream_replace_day_timeline(plan.date) if day_view_stream_context?
        end
        render turbo_stream: streams
      end
      format.html { redirect_back fallback_location: root_path }
    end
  end

  def defer
    prev_date = @task.day_plan&.date
    was_timeboxed = @task.timeboxed?
    case params[:defer_to]
    when "tomorrow"
      @task.defer_to_tomorrow!
    when "sometime"
      @task.defer_to_sometime!
      SyncSometimeTodoToHeyJob.perform_later(@task.id) if current_user.hey_connected? && !Rails.env.test?
    end

    respond_to do |format|
      format.turbo_stream do
        streams = [ turbo_stream.remove("task_#{@task.id}") ]
        if prev_date && was_timeboxed && day_view_stream_context?
          streams << stream_replace_day_timeline(prev_date)
        end
        render turbo_stream: streams
      end
      format.html { redirect_back fallback_location: root_path }
    end
  end

  def comment
    content = params[:content].to_s.strip
    error = if content.blank?
      "Comment can't be blank."
    elsif !(@task.basecamp? && @task.basecamp_bucket_id.present? && @task.external_id.present?)
      "Cannot comment on this task."
    end

    if error
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(
            "task_comment_#{@task.id}",
            partial: "task_assignments/comment_form",
            locals: { task: @task, error: error }
          ), status: :unprocessable_entity
        end
        format.html { redirect_back fallback_location: root_path, alert: error }
      end
      return
    end

    client = BasecampClient.new(current_user)
    client.create_comment(@task.basecamp_bucket_id, @task.external_id, content: content)

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          "task_comment_#{@task.id}",
          partial: "task_assignments/comment_form",
          locals: { task: @task }
        )
      end
      format.html { redirect_back fallback_location: root_path }
    end
  end

  # Drag HEY-promoted task back to the HEY panel: restore inbox row, remove task.
  def restore_hey_email
    return head :unprocessable_entity unless @task.hey_app_url.present?

    email = current_user.hey_emails.find_by(hey_url: @task.hey_app_url)
    return head :not_found unless email

    week_start = Date.current.beginning_of_week(:monday)
    day_ctx    = day_view_stream_context?
    prev_date  = @task.day_plan&.date
    was_sometime = @task.week_bucket == "sometime"
    had_timebox = @task.timeboxed?
    task_id = @task.id

    ActiveRecord::Base.transaction do
      email.update!(triaged_at: nil)
      @task.destroy!
    end

    respond_to do |format|
      format.turbo_stream do
        streams = [ turbo_stream.remove("task_#{task_id}") ]

        if prev_date
          if day_ctx
            streams << stream_replace_day_plan_tasks(prev_date)
            streams << stream_replace_day_timeline(prev_date) if had_timebox
          else
            plan = current_user.day_plans.find_by(date: prev_date)
            streams << turbo_stream.replace("day_#{prev_date}",
              partial: "weeks/day_column",
              locals: {
                date: prev_date,
                tasks: current_user.task_assignments
                         .for_week(prev_date.beginning_of_week(:monday))
                         .where(day_plan: plan)
                         .ordered,
                events: day_column_calendar_events_for(current_user, prev_date)
              })
          end
        elsif was_sometime
          streams << turbo_stream.replace("sometime_row",
            partial: "weeks/sometime_row",
            locals: { tasks: current_user.task_assignments
              .where(week_bucket: "sometime", week_start_date: week_start)
              .ordered })
        end

        streams << turbo_stream.prepend("hey-inbox-list",
          partial: "layouts/hey_inbox_row",
          locals: { email: email.reload })

        render turbo_stream: streams
      end
      format.html { redirect_back fallback_location: root_path }
    end
  end

  def timebox
    date = Date.parse(params[:date])

    if ActiveModel::Type::Boolean.new.cast(params[:clear])
      clear_timebox_for!(date)
      return
    end

    hour = params[:hour].to_i
    minute = params[:minute].to_i

    starts_at = ActiveSupport::TimeZone[current_user.timezone].local(
      date.year, date.month, date.day, hour, minute
    )
    starts_at = TimelineLayout.snap_zoned_time_to_grid(starts_at, current_user.timezone)

    duration = TimelineLayout.snap_duration_minutes(
      params[:duration_minutes].presence&.to_i || @task.planned_duration_minutes || 60
    )

    @task.update!(
      planned_start_at: starts_at,
      planned_duration_minutes: duration
    )

    tb_enqueued = current_user.hey_connected?
    SyncTimeboxToHeyJob.perform_later(@task.id) if tb_enqueued

    respond_to do |format|
      format.turbo_stream { render turbo_stream: stream_replace_day_timeline(date) }
      format.html { redirect_to day_path(date) }
    end
  end

  private

  def clear_timebox_for!(date)
    CalendarEvent.destroy_daybreak_timebox_mirror!(current_user, @task.id)
    if current_user.hey_connected? && @task.hey_calendar_event_id.present?
      begin
        HeyClient.new(current_user).delete_timebox_mirror_remote_id(@task.hey_calendar_event_id)
      rescue StandardError => e
        Rails.logger.warn("clear timebox HEY delete failed: #{e.message}")
      end
    end

    @task.update!(planned_start_at: nil, hey_calendar_event_id: nil)

    respond_to do |format|
      format.turbo_stream { render turbo_stream: stream_replace_day_timeline(date) }
      format.html { redirect_to day_path(date) }
    end
  end

  def stream_replace_day_timeline(date)
    day_plan = current_user.day_plans.find_by(date: date)
    tz = current_user.timezone
    timeline_events = current_user.calendar_events
      .for_date(date, tz)
      .chronological
      .map { |e| e.to_timeline_hash(tz) }
      .compact
      .reject { |h| h[:all_day] }
    turbo_stream.replace(
      "timeline_#{date}",
      partial: "days/timeline",
      locals: {
        date: date,
        events: timeline_events,
        tasks: day_plan ? day_plan.task_assignments.ordered : [],
        timezone: tz
      }
    )
  end

  def clear_hey_mirrored_todo_if_present!
    return if @task.hey_mirrored_todo_id.blank?
    return unless current_user.hey_connected?

    DeleteHeyMirroredTodoJob.perform_later(current_user.id, @task.hey_mirrored_todo_id)
  end

  # Day view has no turbo-frame#day_* or #sometime_row; only #day_plan_tasks_DATE.
  def day_view_stream_context?
    return true if params[:view].to_s == "day"

    ref = request.referer.to_s
    return false if ref.blank?

    URI.parse(ref).path.match?(%r{/days/\d{4}-\d{2}-\d{2}})
  rescue URI::InvalidURIError
    false
  end

  def stream_replace_day_plan_tasks(date)
    plan = current_user.day_plans.find_by(date: date)
    tasks = plan ? current_user.task_assignments.where(day_plan: plan).ordered : TaskAssignment.none
    turbo_stream.replace(
      "day_plan_tasks_#{date}",
      partial: "days/day_plan_tasks",
      locals: { date: date, tasks: tasks }
    )
  end

  def set_task
    @task = current_user.task_assignments.find(params[:id])
  end

  def task_params
    params.require(:task_assignment).permit(:title, :description, :size, :planned_duration_minutes, :status)
  end
end
