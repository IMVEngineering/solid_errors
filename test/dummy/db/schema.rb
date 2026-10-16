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

ActiveRecord::Schema[7.1].define(version: 2026_10_16_000000) do
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
    t.bigint "error_id", null: false
    t.text "backtrace"
    t.json "context"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["error_id"], name: "index_solid_errors_occurrences_on_error_id"
  end

  create_table "solid_errors_events", force: :cascade do |t|
    t.bigint "error_id", null: false
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
