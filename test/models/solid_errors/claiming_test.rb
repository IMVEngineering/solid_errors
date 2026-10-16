require "test_helper"

class SolidErrors::ClaimingTest < ActiveSupport::TestCase
  ANN = {id: "1", name: "Ann"}.freeze
  BOB = {id: "2", name: "Bob"}.freeze

  setup do
    SolidErrors.assignees = -> { [ANN, BOB] }
    report_raised_error("oof")
    @error = SolidErrors::Error.last
  end

  teardown do
    SolidErrors.assignees = nil
  end

  test "claiming assigns the error and records who did it" do
    @error.claim!(assignee: ANN, actor: BOB)

    assert_equal ["1", "Ann"], @error.reload.values_at(:claimed_by_id, :claimed_by_name)
    event = @error.events.sole
    assert_equal ["claimed", "2", "Bob", "1", "Ann"], event.values_at(:action, :actor_id, :actor_name, :assignee_id, :assignee_name)
  end

  test "claiming an already claimed error reassigns it" do
    @error.claim!(assignee: ANN, actor: ANN)
    @error.claim!(assignee: BOB, actor: ANN)

    assert_equal "Bob", @error.reload.claimed_by_name
    assert_equal %w[claimed claimed], @error.events.map(&:action)
  end

  test "unclaiming clears the claim and records it" do
    @error.claim!(assignee: ANN, actor: ANN)
    @error.unclaim!(actor: BOB)

    assert_nil @error.reload.claimed_by_id
    assert_equal ["unclaimed", "Bob", "Ann"], @error.events.last.values_at(:action, :actor_name, :assignee_name)
  end

  test "resolving clears the claim and records who resolved it" do
    @error.claim!(assignee: ANN, actor: ANN)

    @error.update!(resolved_at: Time.current, resolving_actor: BOB)

    assert_nil @error.reload.claimed_by_id
    assert_equal ["resolved", "Bob"], @error.events.last.values_at(:action, :actor_name)
  end

  test "an error that occurs again after being resolved is reopened by nobody" do
    @error.update!(resolved_at: Time.current, resolving_actor: BOB)

    report_raised_error("oof")

    assert_equal ["reopened", nil], @error.events.last.values_at(:action, :actor_id)
  end

  test "reopening by hand records who did it" do
    @error.update!(resolved_at: Time.current)

    @error.update!(resolved_at: nil, resolving_actor: ANN)

    assert_equal ["reopened", "Ann"], @error.events.last.values_at(:action, :actor_name)
  end

  test "repeat occurrences of an unresolved error record nothing" do
    report_raised_error("oof")

    assert_empty @error.events
  end

  test "events read as sentences" do
    @error.claim!(assignee: ANN, actor: ANN)
    @error.claim!(assignee: BOB, actor: ANN)
    @error.unclaim!(actor: BOB)
    @error.update!(resolved_at: Time.current)
    report_raised_error("oof")

    assert_equal [
      "Claimed by Ann",
      "Assigned to Bob by Ann",
      "Unclaimed by Bob",
      "Resolved",
      "Reopened by a new occurrence"
    ], @error.events.order(:id).map(&:description)
  end

  test "destroying an error destroys its events" do
    @error.claim!(assignee: ANN, actor: ANN)
    @error.update!(resolved_at: Time.current)

    @error.destroy!

    assert_equal 0, SolidErrors::Event.count
  end

  test "without claiming configured, resolving and reopening record nothing and touch no claim" do
    SolidErrors.assignees = nil

    @error.update!(resolved_at: Time.current)
    report_raised_error("oof")

    assert_equal 0, SolidErrors::Event.count
  end

  test "without the events table, errors resolve, reopen and destroy as before" do
    ActiveRecord::Base.connection.drop_table :solid_errors_events
    SolidErrors::Event.reset_column_information

    @error.update!(resolved_at: Time.current)
    report_raised_error("oof")
    @error.reload.update!(resolved_at: Time.current)
    @error.destroy!

    assert_not SolidErrors::Error.exists?(@error.id)
  ensure
    SolidErrors::Event.reset_column_information
  end

  private

  def report_raised_error(message)
    raise StandardError, message
  rescue => error
    Rails.error.report(error)
  end
end
