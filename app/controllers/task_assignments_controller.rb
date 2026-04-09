class TaskAssignmentsController < ApplicationController
  before_action :set_task, only: [ :show, :update, :destroy, :move, :cycle_size, :complete, :defer, :timebox, :comment ]

  def show
    @bc_comments = []
    if @task.basecamp? && @task.basecamp_bucket_id.present? && @task.external_id.present?
      begin
        client = BasecampClient.new(current_user)
        @bc_comments = Array(client.comments(@task.basecamp_bucket_id, @task.external_id))
      rescue StandardError
        @bc_comments = []
      end
    end

    respond_to do |format|
      format.turbo_stream { render :show }
      format.html { render :show }
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
      format.turbo_stream { render turbo_stream: turbo_stream.append("day_#{day_plan.date}", partial: "shared/task_card", locals: { task: @task, compact: true }) }
      format.html { redirect_back fallback_location: root_path }
    end
  end

  def update
    @task.update!(task_params)
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace("task_#{@task.id}", partial: "shared/task_card", locals: { task: @task, compact: true })
      end
      format.html { redirect_back fallback_location: root_path }
    end
  end

  def destroy
    @task.destroy!
    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream.remove("task_#{@task.id}") }
      format.html { redirect_back fallback_location: root_path }
    end
  end

  def move
    from_inbox = params[:from_inbox] == "1"
    week_start = Date.current.beginning_of_week(:monday)

    if params[:target_bucket] == "inbox"
      source_date = params[:source_date].present? ? Date.parse(params[:source_date]) : nil
      @task.update!(day_plan: nil, week_start_date: nil, week_bucket: "inbox", position: 0)

      respond_to do |format|
        format.turbo_stream do
          streams = [ turbo_stream.remove("task_#{@task.id}") ]

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
                events: []
              })
          end

          streams << turbo_stream.replace("sometime_row",
            partial: "weeks/sometime_row",
            locals: { tasks: current_user.task_assignments
              .where(week_bucket: "sometime", week_start_date: week_start).ordered })

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

      sometime_tasks = current_user.task_assignments
        .where(week_bucket: "sometime", week_start_date: week_start)
        .ordered

      respond_to do |format|
        format.turbo_stream do
          streams = [
            turbo_stream.replace("sometime_row",
              partial: "weeks/sometime_row",
              locals: { tasks: sometime_tasks })
          ]
          streams << turbo_stream.remove("inbox_task_#{@task.id}") if from_inbox
          render turbo_stream: streams
        end
        format.html { redirect_back fallback_location: root_path }
      end
    else
      target_date = Date.parse(params[:target_date])
      target_plan = current_user.day_plans.find_or_create_by!(date: target_date)

      @task.update!(
        day_plan: target_plan,
        week_start_date: target_date.beginning_of_week(:monday),
        week_bucket: "day",
        position: params[:position].to_i
      )

      respond_to do |format|
        format.turbo_stream do
          streams = [
            turbo_stream.replace("day_#{target_date}",
              partial: "weeks/day_column",
              locals: {
                date: target_date,
                tasks: current_user.task_assignments
                         .for_week(target_date.beginning_of_week(:monday))
                         .where(day_plan: target_plan)
                         .ordered,
                events: []
              })
          ]

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
                  events: []
                })
            end
          end

          streams << turbo_stream.remove("inbox_task_#{@task.id}") if from_inbox
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
    @task.complete!(rotation: rotation)
    WriteCompletionJob.perform_later(@task.id) if @task.basecamp? || @task.hey?

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: [
          turbo_stream.remove("task_#{@task.id}"),
          turbo_stream.append("day_#{@task.day_plan&.date}_completed",
            partial: "shared/task_card",
            locals: { task: @task, compact: true })
        ]
      end
      format.html { redirect_back fallback_location: root_path }
    end
  end

  def defer
    case params[:defer_to]
    when "tomorrow"
      @task.defer_to_tomorrow!
    when "sometime"
      @task.defer_to_sometime!
    end

    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream.remove("task_#{@task.id}") }
      format.html { redirect_back fallback_location: root_path }
    end
  end

  def comment
    content = params[:content].to_s.strip
    return head :unprocessable_entity if content.blank?

    unless @task.basecamp? && @task.basecamp_bucket_id.present? && @task.external_id.present?
      return head :unprocessable_entity
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

  def timebox
    date = Date.parse(params[:date])
    hour = params[:hour].to_i
    minute = params[:minute].to_i

    starts_at = ActiveSupport::TimeZone[current_user.timezone].local(
      date.year, date.month, date.day, hour, minute
    )

    @task.update!(
      planned_start_at: starts_at,
      planned_duration_minutes: @task.planned_duration_minutes || 60
    )

    SyncTimeboxToHeyJob.perform_later(@task.id) if current_user.hey_connected?

    day_plan = current_user.day_plans.find_by(date: date)
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          "timeline_#{date}",
          partial: "days/timeline",
          locals: {
            date: date,
            events: [],
            tasks: current_user.task_assignments
                     .where(day_plan: day_plan)
                     .ordered
          }
        )
      end
      format.html { redirect_to day_path(date) }
    end
  end

  private

  def set_task
    @task = current_user.task_assignments.find(params[:id])
  end

  def task_params
    params.require(:task_assignment).permit(:title, :description, :size, :planned_duration_minutes, :status)
  end
end
