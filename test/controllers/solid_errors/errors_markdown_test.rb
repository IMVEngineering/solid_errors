require "test_helper"

class SolidErrors::ErrorsMarkdownTest < ActionDispatch::IntegrationTest
  setup do
    report_errors(3)
    @error = SolidErrors::Error.last
  end

  test "serves the newest occurrence as plain text by default" do
    newest = @error.occurrences.order(created_at: :desc).first
    newest.update!(context: {"marker" => "newest"})

    get solid_errors.error_path(@error, format: :md)

    assert_response :success
    assert_equal "text/plain", response.media_type
    assert_includes response.body, "## Exception: StandardError"
    assert_includes response.body, "- marker: newest"
    assert_equal 1, response.body.scan("## Occurrence").size
  end

  test "includes the requested number of occurrences and prints the header once" do
    get solid_errors.error_path(@error, format: :md, limit: 2)

    assert_equal 1, response.body.scan("## Exception: StandardError").size
    assert_equal 2, response.body.scan("## Occurrence").size
  end

  test "clamps the limit between 1 and 25" do
    report_errors(30)

    get solid_errors.error_path(@error, format: :md, limit: 100)
    assert_equal 25, response.body.scan("## Occurrence").size

    get solid_errors.error_path(@error, format: :md, limit: 0)
    assert_equal 1, response.body.scan("## Occurrence").size

    get solid_errors.error_path(@error, format: :md, limit: "nope")
    assert_equal 1, response.body.scan("## Occurrence").size
  end

  test "prints source context once per application frame across occurrences" do
    routes = Rails.root.join("config/routes.rb")
    line = File.readlines(routes).index { |code| code.include?("mount SolidErrors::Engine") } + 1
    @error.occurrences.update_all(backtrace: "#{routes}:#{line}:in 'block in <main>'")

    get solid_errors.error_path(@error, format: :md, limit: 3)

    assert_equal 1, response.body.scan("### Source Context").size
    assert_equal 1, response.body.scan("#{line}:   mount SolidErrors::Engine").size
  end

  test "does not HTML-escape the output" do
    @error.update!(message: %(undefined method `<=>' for "a" & 'b'))

    get solid_errors.error_path(@error, format: :md)

    assert_includes response.body, %(undefined method `<=>' for "a" & 'b')
  end

  test "host apps can override the markdown partials" do
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "solid_errors/errors/markdown"))
      File.write(File.join(dir, "solid_errors/errors/markdown/_preamble.text.erb"), "Fix this <%= error.exception_class %> please.\n")
      original = SolidErrors::ErrorsController.view_paths
      SolidErrors::ErrorsController.prepend_view_path(dir)

      get solid_errors.error_path(@error, format: :md)

      assert response.body.start_with?("Fix this StandardError please.\n")
    ensure
      SolidErrors::ErrorsController.view_paths = original
    end
  end

  private

  def report_errors(count)
    count.times do
      raise StandardError, "oof"
    rescue => error
      Rails.error.report(error)
    end
  end
end
