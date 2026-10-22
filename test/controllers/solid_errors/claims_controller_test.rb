require "test_helper"

class SolidErrors::ClaimsControllerTest < ActionDispatch::IntegrationTest
  ANN = {id: "1", name: "Ann"}.freeze
  BOB = {id: "2", name: "Bob"}.freeze

  setup do
    SolidErrors.current_actor = ->(_controller) { ANN }
    SolidErrors.assignees = -> { [ANN, BOB] }
    report_error("oof")
    @error = SolidErrors::Error.last
  end

  teardown do
    SolidErrors.current_actor = nil
    SolidErrors.assignees = nil
  end

  test "claims an error for the signed-in user" do
    post solid_errors.error_claim_path(@error), params: {assignee_id: "1"}

    assert_redirected_to solid_errors.error_path(@error)
    assert_equal "Ann", @error.reload.claimed_by_name
    assert_equal ["Ann", "Ann"], @error.events.sole.values_at(:actor_name, :assignee_name)
  end

  test "assigns an error to someone else" do
    post solid_errors.error_claim_path(@error), params: {assignee_id: "2"}

    assert_equal "Bob", @error.reload.claimed_by_name
    assert_equal "Ann", @error.events.sole.actor_name
  end

  test "claims for the signed-in user even when they aren't an assignee" do
    SolidErrors.assignees = nil

    post solid_errors.error_claim_path(@error), params: {assignee_id: "1"}

    assert_equal "Ann", @error.reload.claimed_by_name
  end

  test "assigns without a signed-in user when only assignees are configured" do
    SolidErrors.current_actor = nil

    post solid_errors.error_claim_path(@error), params: {assignee_id: "2"}

    assert_equal "Bob", @error.reload.claimed_by_name
    assert_nil @error.events.sole.actor_id
  end

  test "refuses someone who isn't an assignee" do
    post solid_errors.error_claim_path(@error), params: {assignee_id: "99"}

    assert_redirected_to solid_errors.error_path(@error)
    assert_nil @error.reload.claimed_by_id
  end

  test "shows the claim controls in their own row, not the action bar" do
    @error.claim!(assignee: BOB, actor: ANN)

    get solid_errors.error_path(@error)

    assert_select "#error-claim form[action='#{solid_errors.error_claim_path(@error)}']", count: 2
    assert_select "#error-claim #error-history"
    assert_select "#error-actions form[action='#{solid_errors.error_claim_path(@error)}']", count: 0
  end

  test "unclaims an error" do
    @error.claim!(assignee: BOB, actor: BOB)

    delete solid_errors.error_claim_path(@error)

    assert_redirected_to solid_errors.error_path(@error)
    assert_nil @error.reload.claimed_by_id
    assert_equal "Ann", @error.events.last.actor_name
  end

  test "refuses to claim an error that was resolved since the page loaded" do
    @error.update!(resolved_at: Time.current)

    post solid_errors.error_claim_path(@error), params: {assignee_id: "1"}

    assert_redirected_to solid_errors.error_path(@error)
    assert_nil @error.reload.claimed_by_id
    assert_equal %w[resolved], @error.events.pluck(:action)
  end

  test "claim routes are not found without claiming configured" do
    SolidErrors.current_actor = nil
    SolidErrors.assignees = nil

    post solid_errors.error_claim_path(@error), params: {assignee_id: "1"}

    assert_response :not_found
    assert_nil @error.reload.claimed_by_id
  end

  test "resolving from the dashboard records who resolved it" do
    @error.claim!(assignee: BOB, actor: BOB)

    patch solid_errors.error_path(@error), params: {error: {resolved_at: Time.current}}

    assert_nil @error.reload.claimed_by_id
    assert_equal ["resolved", "Ann"], @error.events.last.values_at(:action, :actor_name)
  end

  test "the error page offers claiming for me and each other assignee, and shows the history" do
    @error.claim!(assignee: BOB, actor: ANN)

    get solid_errors.error_path(@error)

    assert_response :success
    assert_equal [["1", "Claim for me"], ["2", "Bob"]],
      css_select("select[name=assignee_id] option").map { |option| [option["value"], option.text.strip] }
    assert_select "select[name=assignee_id] option[selected][value='2']"
    assert_select "form[action='#{solid_errors.error_claim_path(@error)}'] input[name=_method][value=delete]"
    assert_select "#error-history li", text: /Assigned to Bob by Ann/
  end

  test "a resolved error offers no claiming but keeps its history" do
    @error.update!(resolved_at: Time.current, resolving_actor: ANN)

    get solid_errors.error_path(@error)

    assert_select "select[name=assignee_id]", count: 0
    assert_select "#error-history li", text: /Resolved by Ann/
  end

  test "the error page shows nothing about claiming without it configured" do
    SolidErrors.current_actor = nil
    SolidErrors.assignees = nil

    get solid_errors.error_path(@error)

    assert_response :success
    assert_select "select[name=assignee_id]", count: 0
    assert_select "#error-history", count: 0
  end

  test "the errors list shows who claimed each error and filters by claim" do
    report_error("argh")
    mine = SolidErrors::Error.find_by!(message: "oof")
    unclaimed = SolidErrors::Error.find_by!(message: "argh")
    mine.claim!(assignee: ANN)

    get solid_errors.errors_path
    assert_select "th", text: "Claimed by"
    assert_select "##{dom_id(mine)} td", text: "Ann"
    assert_select "nav[aria-label='Claim filter'] a", text: "Mine"

    get solid_errors.errors_path(claimed: "mine")
    assert_select "##{dom_id(mine)}"
    assert_select "##{dom_id(unclaimed)}", count: 0

    get solid_errors.errors_path(claimed: "unclaimed")
    assert_select "##{dom_id(mine)}", count: 0
    assert_select "##{dom_id(unclaimed)}"
  end

  test "the errors list offers no Mine filter without a signed-in user" do
    SolidErrors.current_actor = nil

    get solid_errors.errors_path

    assert_select "nav[aria-label='Claim filter'] a", text: "Unclaimed"
    assert_select "nav[aria-label='Claim filter'] a", text: "Mine", count: 0
  end

  test "the errors list shows nothing about claiming without it configured" do
    SolidErrors.current_actor = nil
    SolidErrors.assignees = nil

    get solid_errors.errors_path(claimed: "mine")

    assert_response :success
    assert_select "th", text: "Claimed by", count: 0
    assert_select "nav[aria-label='Claim filter']", count: 0
    assert_select "##{dom_id(@error)}"
  end

  private

  def dom_id(record)
    ActionView::RecordIdentifier.dom_id(record)
  end

  def report_error(message)
    raise StandardError, message
  rescue => error
    Rails.error.report(error)
  end
end
