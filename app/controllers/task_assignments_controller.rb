class TaskAssignmentsController < ApplicationController
  before_action :set_task, only: [ :update, :destroy, :move, :cycle_size, :complete, :defer ]

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
    redirect_back fallback_location: root_path
  end

  def destroy
    @task.destroy!
    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream.remove("task_#{@task.id}") }
      format.html { redirect_back fallback_location: root_path }
    end
  end

  def move
    target_date = Date.parse(params[:target_date])
    target_plan = current_user.day_plans.find_or_create_by!(date: target_date)

    @task.update!(
      day_plan: target_plan,
      week_start_date: target_date.beginning_of_week(:monday),
      week_bucket: "day",
      position: params[:position].to_i
    )

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_back fallback_location: root_path }
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
    @task.complete!
    WriteCompletionJob.perform_later(@task.id) if @task.basecamp? || @task.hey?

    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream.replace("task_#{@task.id}", partial: "shared/task_card", locals: { task: @task, compact: true }) }
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

  private

  def set_task
    @task = current_user.task_assignments.find(params[:id])
  end

  def task_params
    params.require(:task_assignment).permit(:title, :description, :size, :planned_duration_minutes, :status)
  end
end
