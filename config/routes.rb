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

  # HEY connection (PKCE OAuth + token-paste fallback)
  get    "auth/hey",           to: "hey_connections#new",       as: :auth_hey
  post   "auth/hey",           to: "hey_connections#create",    as: :connect_hey
  get    "auth/hey/authorize", to: "hey_connections#authorize", as: :authorize_hey
  get    "auth/hey/callback",  to: "hey_connections#callback",  as: :auth_hey_callback
  delete "auth/hey",           to: "hey_connections#destroy",   as: :disconnect_hey

  # HEY email actions (triage/dismiss from the right panel, plan via drag)
  resources :hey_emails, only: [ :show ] do
    collection do
      get :more
    end
    member do
      patch :triage
      patch :dismiss
      post  :plan
    end
  end

  # Onboarding
  resource :onboarding, only: [ :show, :update ], controller: "onboarding" do
    post :complete
    get :restart
  end

  # Manual Basecamp sync + inbox pagination
  post "sync/basecamp", to: "sync#basecamp", as: :sync_basecamp
  get  "sync/basecamp/more", to: "sync#basecamp_more", as: :sync_basecamp_more
  post "sync/hey", to: "sync#hey", as: :sync_hey

  # Week view (home)
  root "weeks#show"
  get "weeks/:date", to: "weeks#show", as: :week

  # Day view
  get "days/:date", to: "days#show", as: :day
  get "days/:date/log", to: "daily_logs#show", as: :day_log
  post "days/:date/log", to: "daily_logs#create"
  patch "days/:date/log", to: "daily_logs#update"

  # Daily journal scratchpad (right panel)
  post "journal/:date", to: "journal#upsert", as: :journal_entry
  get "journal/:date/status", to: "journal#hey_badge_status", as: :journal_entry_status

  # Tasks
  resources :task_assignments, only: [ :show, :create, :update, :destroy ] do
    member do
      get   :focus
      post  :comment
      patch :move
      patch :cycle_size
      patch :complete
      patch :defer
      patch :timebox
      patch :restore_hey_email
    end
  end

  # HEY (and future) calendar events shown on the day timeline
  resources :calendar_events, only: [ :update, :destroy ] do
    member do
      patch :slot
    end
  end

  # Local tasks (personal, not in any API)
  resources :local_tasks, only: [ :create, :destroy ]

  # Timer
  resources :timer_sessions, only: [ :create, :update ]

  # Rituals
  get  "ritual/morning",          to: "rituals#morning"
  post "ritual/morning",          to: "rituals#morning_update"
  post "ritual/morning/add_week_events", to: "rituals#morning_add_week_events", as: :ritual_morning_add_week_events
  post "ritual/morning/complete", to: "rituals#morning_complete"
  get  "ritual/evening",          to: "rituals#evening"
  post "ritual/evening",          to: "rituals#evening_update"
  post "ritual/evening/complete", to: "rituals#evening_complete"

  # Weekly check-in
  resource :weekly_checkin, only: [ :show, :update ], controller: "weekly_checkins"

  # Settings
  resource :settings, only: [ :show, :update ], controller: "settings"

  # Proxies Basecamp profile photo (API requires Bearer token; <img> cannot send it).
  get "profile/basecamp_avatar", to: "basecamp_avatars#show", as: :basecamp_avatar
end
