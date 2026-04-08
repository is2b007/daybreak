class LocalTasksController < ApplicationController
  def create
    @task = current_user.local_tasks.create!(title: params[:title], description: params[:description])
    redirect_back fallback_location: root_path
  end

  def destroy
    @task = current_user.local_tasks.find(params[:id])
    @task.destroy!
    redirect_back fallback_location: root_path
  end
end
