class ProjectsController < ApplicationController
  def index
    @projects = Project.all_projects
    @users = User.all_users.index_by(&:user_id)
  end

  def new
    @project = Project.new
    @users = User.all_users
  end

  def create
    @project = Project.new
    @project.project_id = SecureRandom.uuid[0, 8]
    @project.name = params[:name]
    @project.description = params[:description]
    @project.owner_id = params[:owner_id]

    if @project.name.present? && @project.owner_id.present?
      @project.save_as_project
      redirect_to projects_path, notice: "Project created successfully."
    else
      @users = User.all_users
      flash.now[:alert] = "Name and owner are required."
      render :new, status: :unprocessable_entity
    end
  end

  def show
    @project = Project.find_by_project_id(params[:id])
    if @project.nil?
      redirect_to projects_path, alert: "Project not found."
      return
    end
    @tasks = Task.for_project(params[:id])
    @users = User.all_users.index_by(&:user_id)
  end
end
