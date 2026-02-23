class TasksController < ApplicationController
  before_action :set_project, only: [:new, :create, :edit, :update, :destroy, :cycle_status]

  def new
    @task = Task.new
    @users = User.all_users
  end

  def create
    @task = Task.new
    @task.task_id = SecureRandom.uuid[0, 8]
    @task.title = params[:title]
    @task.project_id = params[:project_id]
    @task.assignee_id = params[:assignee_id]
    @task.status = params[:status] || "todo"
    @task.due_date = params[:due_date]
    @task.priority = params[:priority] || "medium"

    if @task.title.present? && @task.due_date.present?
      @task.save_as_task
      redirect_to project_path(@task.project_id), notice: "Task created successfully."
    else
      @users = User.all_users
      flash.now[:alert] = "Title and due date are required."
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @task = Task.find_by_task_id(params[:project_id], params[:id])
    if @task.nil?
      redirect_to project_path(params[:project_id]), alert: "Task not found."
      return
    end
    @users = User.all_users
  end

  def update
    @task = Task.find_by_task_id(params[:project_id], params[:id])
    if @task.nil?
      redirect_to project_path(params[:project_id]), alert: "Task not found."
      return
    end

    old_sk = @task.sk
    old_pk = @task.pk

    @task.title = params[:title]
    @task.assignee_id = params[:assignee_id]
    @task.status = params[:status]
    @task.priority = params[:priority]

    new_due_date = params[:due_date]
    if new_due_date != @task.due_date
      # Due date changed: delete old item and create new one (SK contains due_date)
      client = Aws::DynamoDB::Client.new
      client.delete_item(table_name: "TaskBoard", key: { "pk" => old_pk, "sk" => old_sk })
      @task.due_date = new_due_date
    end

    @task.save_as_task
    redirect_to project_path(params[:project_id]), notice: "Task updated successfully."
  end

  def destroy
    @task = Task.find_by_task_id(params[:project_id], params[:id])
    if @task
      client = Aws::DynamoDB::Client.new
      client.delete_item(
        table_name: "TaskBoard",
        key: { "pk" => @task.pk, "sk" => @task.sk }
      )
    end
    redirect_to project_path(params[:project_id]), notice: "Task deleted."
  end

  def cycle_status
    @task = Task.find_by_task_id(params[:project_id], params[:id])
    if @task
      @task.status = @task.next_status
      @task.save_as_task
    end
    redirect_to project_path(params[:project_id])
  end

  # GSI1: tasks by status
  def by_status
    @status = params[:status]
    @tasks = Task.by_status(@status)
    @users = User.all_users.index_by(&:user_id)
    @projects = Project.all_projects.index_by(&:project_id)
  end

  # GSI2: tasks by assignee
  def by_assignee
    @user = User.find(params[:user_id])
    @tasks = Task.by_assignee(params[:user_id])
    @projects = Project.all_projects.index_by(&:project_id)
  end

  private

  def set_project
    @project = Project.find_by_project_id(params[:project_id])
  end
end
