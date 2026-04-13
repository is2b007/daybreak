# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_04_13_200000) do
  create_table "calendar_events", force: :cascade do |t|
    t.boolean "all_day", default: false, null: false
    t.string "basecamp_bucket_id"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.text "description"
    t.datetime "ends_at"
    t.string "external_id", null: false
    t.string "hey_calendar_id"
    t.string "location"
    t.boolean "show_on_week_board", default: false, null: false
    t.integer "source", null: false
    t.datetime "starts_at", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["user_id", "external_id", "source"], name: "index_calendar_events_on_user_external_and_source", unique: true
    t.index ["user_id", "show_on_week_board"], name: "index_calendar_events_on_user_id_and_show_on_week_board"
    t.index ["user_id", "starts_at"], name: "index_calendar_events_on_user_id_and_starts_at"
    t.index ["user_id"], name: "index_calendar_events_on_user_id"
  end

  create_table "daily_logs", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.date "date", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["user_id", "date"], name: "index_daily_logs_on_user_id_and_date", unique: true
    t.index ["user_id"], name: "index_daily_logs_on_user_id"
  end

  create_table "day_plans", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.date "date", null: false
    t.boolean "evening_ritual_done", default: false, null: false
    t.boolean "morning_ritual_done", default: false, null: false
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["user_id", "date"], name: "index_day_plans_on_user_id_and_date", unique: true
    t.index ["user_id"], name: "index_day_plans_on_user_id"
  end

  create_table "hey_emails", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "dismissed_at"
    t.string "external_id", null: false
    t.integer "folder", null: false
    t.string "hey_url"
    t.string "label"
    t.datetime "received_at", null: false
    t.string "sender_email"
    t.string "sender_name"
    t.text "snippet"
    t.string "subject", null: false
    t.datetime "triaged_at"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["user_id", "external_id"], name: "index_hey_emails_on_user_id_and_external_id", unique: true
    t.index ["user_id", "folder"], name: "index_hey_emails_on_user_id_and_folder"
    t.index ["user_id", "received_at"], name: "index_hey_emails_on_user_id_and_received_at"
    t.index ["user_id"], name: "index_hey_emails_on_user_id"
  end

  create_table "local_journal_entries", force: :cascade do |t|
    t.text "content", null: false
    t.datetime "created_at", null: false
    t.date "date", null: false
    t.string "last_pushed_to_hey_digest"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["user_id", "date"], name: "index_local_journal_entries_on_user_id_and_date", unique: true
    t.index ["user_id"], name: "index_local_journal_entries_on_user_id"
  end

  create_table "local_tasks", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["user_id"], name: "index_local_tasks_on_user_id"
  end

  create_table "local_timer_sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "ended_at"
    t.datetime "started_at", null: false
    t.integer "task_assignment_id"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["task_assignment_id"], name: "index_local_timer_sessions_on_task_assignment_id"
    t.index ["user_id"], name: "index_local_timer_sessions_on_user_id"
  end

  create_table "log_entries", force: :cascade do |t|
    t.text "content", null: false
    t.datetime "created_at", null: false
    t.integer "daily_log_id", null: false
    t.datetime "logged_at", null: false
    t.datetime "updated_at", null: false
    t.index ["daily_log_id"], name: "index_log_entries_on_daily_log_id"
  end

  create_table "task_assignments", force: :cascade do |t|
    t.integer "actual_duration_minutes"
    t.string "basecamp_bucket_id"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.integer "day_plan_id"
    t.text "description"
    t.string "external_id"
    t.string "hey_app_url"
    t.string "hey_calendar_event_id"
    t.string "hey_mirrored_todo_id"
    t.integer "planned_duration_minutes"
    t.datetime "planned_start_at"
    t.integer "position"
    t.string "project_name"
    t.integer "size", default: 1, null: false
    t.integer "source", default: 0, null: false
    t.integer "stamp_rotation_degrees"
    t.integer "status", default: 0, null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.string "week_bucket", default: "day", null: false
    t.date "week_start_date"
    t.index ["day_plan_id"], name: "index_task_assignments_on_day_plan_id"
    t.index ["external_id", "source"], name: "index_task_assignments_on_external_id_and_source"
    t.index ["hey_mirrored_todo_id"], name: "index_task_assignments_on_hey_mirrored_todo_id"
    t.index ["user_id", "day_plan_id"], name: "index_task_assignments_on_user_id_and_day_plan_id"
    t.index ["user_id", "planned_start_at"], name: "index_task_assignments_on_user_id_and_planned_start_at"
    t.index ["user_id", "week_start_date"], name: "index_task_assignments_on_user_id_and_week_start_date"
    t.index ["user_id"], name: "index_task_assignments_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "basecamp_access_token"
    t.string "basecamp_account_id"
    t.string "basecamp_avatar_url"
    t.string "basecamp_refresh_token"
    t.datetime "basecamp_token_expires_at"
    t.string "basecamp_uid", null: false
    t.datetime "created_at", null: false
    t.string "email"
    t.string "hey_access_token"
    t.string "hey_default_calendar_id"
    t.string "hey_refresh_token"
    t.datetime "hey_token_expires_at"
    t.date "last_open_date"
    t.string "name", null: false
    t.boolean "onboarded", default: false, null: false
    t.string "stamp_choice", default: "red_done", null: false
    t.string "sundown_time", default: "17:00", null: false
    t.string "theme", default: "system", null: false
    t.string "timezone", default: "UTC", null: false
    t.datetime "updated_at", null: false
    t.decimal "work_hours_target", default: "5.5", null: false
    t.index ["basecamp_uid"], name: "index_users_on_basecamp_uid", unique: true
  end

  create_table "weekly_goals", force: :cascade do |t|
    t.boolean "completed", default: false, null: false
    t.datetime "created_at", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.date "week_start_date", null: false
    t.index ["user_id", "week_start_date"], name: "index_weekly_goals_on_user_id_and_week_start_date"
    t.index ["user_id"], name: "index_weekly_goals_on_user_id"
  end

  add_foreign_key "calendar_events", "users"
  add_foreign_key "daily_logs", "users"
  add_foreign_key "day_plans", "users"
  add_foreign_key "hey_emails", "users"
  add_foreign_key "local_journal_entries", "users"
  add_foreign_key "local_tasks", "users"
  add_foreign_key "local_timer_sessions", "task_assignments"
  add_foreign_key "local_timer_sessions", "users"
  add_foreign_key "log_entries", "daily_logs"
  add_foreign_key "task_assignments", "day_plans"
  add_foreign_key "task_assignments", "users"
  add_foreign_key "weekly_goals", "users"
end
