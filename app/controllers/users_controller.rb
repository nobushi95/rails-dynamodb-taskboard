class UsersController < ApplicationController
  def index
    @users = User.all_users
  end

  def new
    @user = User.new
  end

  def create
    @user = User.new
    @user.user_id = SecureRandom.uuid[0, 8]
    @user.name = params[:name]
    @user.email = params[:email]

    if @user.name.present? && @user.email.present?
      @user.save_as_user
      redirect_to users_path, notice: "User created successfully."
    else
      flash.now[:alert] = "Name and email are required."
      render :new, status: :unprocessable_entity
    end
  end
end
