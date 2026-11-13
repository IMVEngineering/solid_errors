require "test_helper"

class SolidErrors::PagerTest < ActionView::TestCase
  def page_for(count, params = {})
    SolidErrors::ApplicationController::Page.new(Array.new(count), params, default_items: 25)
  end

  test "shows the range and links to the other pages" do
    page = page_for(60, page: 2)
    render partial: "solid_errors/pager", locals: {page: page, noun: "errors"}

    assert_select "strong", text: "26-50"
    assert_select "nav[aria-label=Pages] a[href][aria-label=First]"
    assert_select "nav[aria-label=Pages] a[href][aria-label=Last]"
  end

  test "links keep the allowlisted query params and replace page" do
    request.query_parameters.merge!("scope" => "resolved", "items" => "5", "page" => "2", "other" => "x")
    render partial: "solid_errors/pager", locals: {page: page_for(100, page: 2), noun: "errors"}

    assert_select "a[aria-label=Next][href=?]", "?items=5&page=3&scope=resolved"
  end

  test "request params that look like url options do not leak into links" do
    request.query_parameters.merge!("host" => "evil.example", "script_name" => "/x")
    render partial: "solid_errors/pager", locals: {page: page_for(100), noun: "errors"}

    assert_select "a[aria-label=Next][href=?]", "?page=2"
  end

  test "disables the links on a single page" do
    render partial: "solid_errors/pager", locals: {page: page_for(3), noun: "errors"}

    assert_select "strong", text: "3"
    assert_select "nav a[href]", count: 0
    assert_select "nav a[aria-disabled=true]", count: 4
  end

  test "an empty list names what is missing" do
    render partial: "solid_errors/pager", locals: {page: page_for(0), noun: "errors"}

    assert_includes rendered, "No errors found"
  end
end
