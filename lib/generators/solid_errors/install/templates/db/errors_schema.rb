# frozen_string_literal: true

ActiveRecord::Schema[7.1].define(version: 1) do
  create_table "solid_errors", force: :cascade do |t|
    t.text "exception_class", null: false
    t.text "message", null: false
    t.text "severity", null: false
    t.text "source"
    t.datetime "resolved_at"
    t.string "fingerprint", limit: 64, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "claimed_by_id"
    t.string "claimed_by_name"
    t.index ["claimed_by_id"], name: "index_solid_errors_on_claimed_by_id"
    t.index ["fingerprint"], name: "index_solid_errors_on_fingerprint", unique: true
    t.index ["resolved_at"], name: "index_solid_errors_on_resolved_at"
  end

  create_table "solid_errors_occurrences", force: :cascade do |t|
    t.integer "error_id", null: false
    t.text "backtrace"
    t.json "context"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["error_id"], name: "index_solid_errors_occurrences_on_error_id"
  end

  create_table "solid_errors_events", force: :cascade do |t|
    t.integer "error_id", null: false
    t.string "action", null: false
    t.string "actor_id"
    t.string "actor_name"
    t.string "assignee_id"
    t.string "assignee_name"
    t.datetime "created_at", null: false
    t.index ["error_id"], name: "index_solid_errors_events_on_error_id"
  end

  add_foreign_key "solid_errors_events", "solid_errors", column: "error_id"
  add_foreign_key "solid_errors_occurrences", "solid_errors", column: "error_id"
end
