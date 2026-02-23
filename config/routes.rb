Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  resources :users, only: [:index, :new, :create]
  resources :projects, only: [:index, :new, :create, :show] do
    resources :tasks, only: [:new, :create, :edit, :update, :destroy] do
      member { patch :cycle_status }
    end
  end
  get "tasks/by_status/:status", to: "tasks#by_status", as: :tasks_by_status
  get "tasks/by_assignee/:user_id", to: "tasks#by_assignee", as: :tasks_by_assignee

  root "projects#index"
end
