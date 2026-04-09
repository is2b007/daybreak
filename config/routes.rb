Rails.application.routes.draw do
  # Health check
  get "up" => "rails/health#show", as: :rails_health_check

  # Dev backdoor login (development only)
  if Rails.env.development?
    get "dev/login/:user_id", to: "dev#login", as: :dev_login
  end

  # Authentication
  get  "login",                   to: "sessions#new",     as: :login
  get  "auth/basecamp",           to: "sessions#new",     as: :auth_basecamp
  get  "auth/basecamp/callback",  to: "sessions#create",  as: :auth_basecamp_callback
  delete "logout",                to: "sessions#destroy",  as: :logout

  # HEY OAuth
  get  "auth/hey",                to: "hey_connections#new",    as: :auth_hey
  get  "auth/hey/callback",       to: "hey_connections#create", as: :auth_hey_callback
  delete "auth/hey",              to: "hey_connections#destroy", as: :disconnect_hey

  # HEY email triage
  resource :triage, only: [ :show ], controller: "triage"
  resources :hey_emails, only: [] do
    member do
      patch :triage
      patch :dismiss
    end
  end

  # Onboarding
  resource :onboarding, only: [ :show, :update ], controller: "onboarding" do
    post :complete
  end

  # Manual Basecamp sync
  post "sync/basecamp", to: "sync#basecamp", as: :sync_basecamp

  # Week view (home)
  root "weeks#show"
  get "weeks/:date", to: "weeks#show", as: :week

  # Day view
  get "days/:date", to: "days#show", as: :day
  get "days/:date/log", to: "daily_logs#show", as: :day_log
  post "days/:date/log", to: "daily_logs#create"
  patch "days/:date/log", to: "daily_logs#update"

  # Tasks
  resources :task_assignments, only: [ :show, :create, :update, :destroy ] do
    member do
      patch :move
      patch :cycle_size
      patch :complete
      patch :defer
      patch :timebox
    end
  end

  # Local tasks (personal, not in any API)
  resources :local_tasks, only: [ :create, :destroy ]

  # Timer
  resources :timer_sessions, only: [ :create, :update ]

  # Rituals
  get  "ritual/morning",          to: "rituals#morning"
  post "ritual/morning",          to: "rituals#morning_update"
  post "ritual/morning/complete", to: "rituals#morning_complete"
  get  "ritual/evening",          to: "rituals#evening"
  post "ritual/evening",          to: "rituals#evening_update"
  post "ritual/evening/complete", to: "rituals#evening_complete"

  # Weekly check-in
  resource :weekly_checkin, only: [ :show, :update ], controller: "weekly_checkins"

  # Settings
  resource :settings, only: [ :show, :update ], controller: "settings"
end
