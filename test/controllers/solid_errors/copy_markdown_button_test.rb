require "test_helper"

class SolidErrors::CopyMarkdownButtonTest < ActionDispatch::IntegrationTest
  test "copies the newest occurrence with no menu when there is only one" do
    error = report_errors(1)

    get solid_errors.error_path(error)

    assert_equal solid_errors.error_path(error, format: :md), css_select("a[data-copy-markdown]").first["href"]
    assert_equal ["Copy Markdown"], copy_labels
  end

  test "offers every occurrence when there are few" do
    error = report_errors(3)

    get solid_errors.error_path(error)

    assert_equal ["Copy Markdown", "All (3)"], copy_labels
    assert_equal solid_errors.error_path(error, format: :md, limit: 3), copy_link("All (3)")["href"]
  end

  test "hides counts that would include every occurrence" do
    error = report_errors(10)

    get solid_errors.error_path(error)

    assert_equal ["Copy Markdown", "Last 5", "All (10)"], copy_labels
  end

  test "caps the menu at the last 25" do
    error = report_errors(26)

    get solid_errors.error_path(error)

    assert_equal ["Copy Markdown", "Last 5", "Last 10", "Last 25"], copy_labels
    assert_equal solid_errors.error_path(error, format: :md, limit: 25), copy_link("Last 25")["href"]
  end

  test "does not inline the markdown into the page" do
    error = report_errors(1)

    get solid_errors.error_path(error)

    assert_empty css_select("template#error-markdown")
  end

  private

  def report_errors(count)
    count.times do
      raise StandardError, "oof"
    rescue => error
      Rails.error.report(error)
    end
    SolidErrors::Error.last
  end

  def copy_labels
    css_select("a[data-copy-markdown]").map { |link| link.text.strip }
  end

  def copy_link(label)
    css_select("a[data-copy-markdown]").find { |link| link.text.strip == label }
  end
end
