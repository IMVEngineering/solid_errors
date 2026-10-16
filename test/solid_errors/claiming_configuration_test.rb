require "test_helper"

class SolidErrors::ClaimingConfigurationTest < ActiveSupport::TestCase
  teardown do
    SolidErrors.current_actor = nil
    SolidErrors.assignees = nil
    SolidErrors::Error.reset_column_information
    SolidErrors::Event.reset_column_information
  end

  test "claiming is off until an app says who its users are" do
    assert_not SolidErrors.claiming?
  end

  test "claiming is on with either current_actor or assignees" do
    SolidErrors.current_actor = ->(_controller) { {id: 1, name: "Ann"} }
    assert SolidErrors.claiming?

    SolidErrors.current_actor = nil
    SolidErrors.assignees = -> { [] }
    assert SolidErrors.claiming?
  end

  test "claiming stays off when the errors database lacks the events table" do
    SolidErrors.assignees = -> { [] }
    ActiveRecord::Base.connection.drop_table :solid_errors_events
    SolidErrors::Event.reset_column_information

    assert_not SolidErrors.claiming?
  end

  test "claiming stays off when the errors table lacks the claim columns" do
    SolidErrors.assignees = -> { [] }
    ActiveRecord::Base.connection.remove_index :solid_errors, :claimed_by_id
    ActiveRecord::Base.connection.remove_column :solid_errors, :claimed_by_id
    SolidErrors::Error.reset_column_information

    assert_not SolidErrors.claiming?
  end

  test "actors and assignees come back with string ids" do
    SolidErrors.current_actor = ->(controller) { {id: 7, name: controller} }
    SolidErrors.assignees = -> { [{id: 7, name: "Ann"}, {id: "b", name: "Bob"}] }

    assert_equal({id: "7", name: "Ann"}, SolidErrors.actor_for("Ann"))
    assert_equal [{id: "7", name: "Ann"}, {id: "b", name: "Bob"}], SolidErrors.assignee_list
  end

  test "no actor when current_actor is unset or returns nil" do
    assert_nil SolidErrors.actor_for(Object.new)

    SolidErrors.current_actor = ->(_controller) {}
    assert_nil SolidErrors.actor_for(Object.new)
  end
end
