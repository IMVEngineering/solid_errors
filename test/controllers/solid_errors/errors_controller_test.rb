require "test_helper"

class SolidErrors::ErrorsControllerTest < ActionDispatch::IntegrationTest
  setup do
    report_errors(2)
    @error = SolidErrors::Error.last
  end

  test "each occurrence has a copy link to its own markdown" do
    get solid_errors.error_path(@error)

    @error.occurrences.each do |occurrence|
      href = solid_errors.error_path(@error, format: :md, occurrence_id: occurrence.id)
      assert_select "section#occurrence_#{occurrence.id} summary a[data-copy-markdown][href=?]", href
    end
  end

  test "markdown for one occurrence includes only that occurrence" do
    occurrence = @error.occurrences.order(:created_at).first
    get solid_errors.error_path(@error, format: :md, occurrence_id: occurrence.id)

    assert_response :success
    assert_equal 1, response.body.scan("## Occurrence").size
    assert_includes response.body, occurrence.created_at.utc.iso8601
  end

  test "markdown for another error's occurrence is not found" do
    other = SolidErrors::Occurrence.where.not(error_id: @error.id).first
    skip "needs a second error" unless other

    get solid_errors.error_path(@error, format: :md, occurrence_id: other.id)
    assert_response :not_found
  end

  test "resolving from the list renders a form that removes its row" do
    get solid_errors.errors_path

    assert_select "tbody tr form[data-remove-row]", count: SolidErrors::Error.unresolved.count
  end

  test "resolving from the show page keeps the normal redirect form" do
    get solid_errors.error_path(@error)

    assert_select "form[data-remove-row]", count: 0
  end

  test "resolving over XHR responds with no content instead of redirecting" do
    patch solid_errors.error_path(@error),
      params: {error: {resolved_at: Time.now}},
      headers: {"X-Requested-With" => "XMLHttpRequest"}

    assert_response :no_content
    assert @error.reload.resolved?
  end

  test "resolving a regular request still redirects to the list" do
    patch solid_errors.error_path(@error), params: {error: {resolved_at: Time.now}}

    assert_redirected_to solid_errors.errors_path
    assert @error.reload.resolved?
  end

  test "occurrence pagination links use the default page size without an items param" do
    report_errors(19)
    get solid_errors.error_path(@error)

    assert_response :success
    assert_equal [solid_errors.error_path(@error, page: 2)] * 2, pagination_hrefs
  end

  test "occurrence pagination links keep the items param" do
    get solid_errors.error_path(@error, items: 1)

    assert_response :success
    assert_equal [solid_errors.error_path(@error, items: 1, page: 2)] * 2, pagination_hrefs
  end

  test "occurrence pagination links ignore url_for options in the request params" do
    get solid_errors.error_path(@error), params: {
      items: 1,
      script_name: "javascript:alert(1)//",
      original_script_name: "javascript:alert(1)//",
      host: "evil.example",
      protocol: "https",
      port: 6666,
      anchor: "x"
    }

    assert_response :success
    assert_equal [solid_errors.error_path(@error, items: 1, page: 2)] * 2, pagination_hrefs
  end

  test "the errors list shows 25 errors per page" do
    create_errors(30)
    get solid_errors.errors_path

    assert_response :success
    assert_select "tbody tr", count: 25
    assert_select "strong", text: "1-25"
    assert_equal [solid_errors.errors_path(page: 2)] * 1, pagination_hrefs.uniq
  end

  test "the second page lists the remaining errors" do
    create_errors(30)
    get solid_errors.errors_path(page: 2)

    assert_select "tbody tr", count: 6
    assert_select "strong", text: "26-31"
  end

  test "the errors list honors the items param" do
    create_errors(10)
    get solid_errors.errors_path(items: 5, page: 2)

    assert_select "tbody tr", count: 5
    assert_includes pagination_hrefs, solid_errors.errors_path(items: 5, page: 1)
  end

  test "a page past the end shows the last page" do
    create_errors(30)
    get solid_errors.errors_path(page: 99)

    assert_response :success
    assert_select "tbody tr", count: 6
  end

  test "a non-positive page or items param does not break the list" do
    get solid_errors.errors_path(page: -3, items: 0)

    assert_response :success
  end

  test "the pager keeps the scope and the tabs reset to the first page" do
    create_errors(30, resolved: true)
    get solid_errors.errors_path(scope: :resolved, page: 2)

    assert_select "tbody tr", count: 5
    assert_includes pagination_hrefs, solid_errors.errors_path(scope: :resolved, page: 1)
    assert_select "nav[aria-label=Tabs] a[href=?]", solid_errors.errors_path(scope: :unresolved)
    assert_select "nav[aria-label=Tabs] a[href=?]", solid_errors.errors_path(scope: :resolved)
  end

  test "the errors list counts only errors that have occurrences" do
    create_errors(3)
    SolidErrors::Error.create!(exception_class: "Orphan", message: "none", severity: "error", source: "x", fingerprint: "orphan")
    get solid_errors.errors_path

    assert_select "tbody tr", count: 4 # 3 plus the one from setup
  end

  test "inline styles and scripts carry the content security policy nonce" do
    get solid_errors.error_path(@error)

    nonce = response.headers["Content-Security-Policy"][/style-src [^;]*'nonce-([^']+)'/, 1]
    assert nonce
    inline_tags = css_select("style, script:not([src])")
    assert_not_empty inline_tags
    inline_tags.each { |tag| assert_equal nonce, tag["nonce"], tag.to_html[0, 40] }
  end

  test "an occurrence reported without a backtrace still renders" do
    # Rails 7 reports exceptions that were never raised without a backtrace
    @error.occurrences.update_all(backtrace: nil)

    get solid_errors.error_path(@error)

    assert_response :success
  end

  test "the application backtrace lists only application frames and the hidden full backtrace lists them all" do
    occurrence = @error.occurrences.last
    occurrence.update!(backtrace: [
      "#{Gem.path.first}/gems/rack-3.0.0/lib/rack.rb:1:in 'call'",
      "#{Rails.root.join("config/routes.rb")}:8:in 'block in <main>'"
    ].join("\n"))

    get solid_errors.error_path(@error)

    assert_select "#backtrace-application-#{occurrence.id} summary", count: 1
    assert_select "#backtrace-application-#{occurrence.id} summary", text: /routes\.rb/
    assert_select "#backtrace-full-#{occurrence.id}[hidden] summary", count: 2
  end

  test "a backtrace without application frames offers the full trace" do
    occurrence = @error.occurrences.last
    occurrence.update!(backtrace: "#{Gem.path.first}/gems/rack-3.0.0/lib/rack.rb:1:in 'call'")

    get solid_errors.error_path(@error)

    assert_select "#backtrace-application-#{occurrence.id}", text: /No application code in backtrace/
    assert_select "#backtrace-application-#{occurrence.id} button[data-backtrace-toggle=full]"
  end

  test "long unbroken messages and context values wrap instead of widening the page" do
    long_value = "https://example.com/#{"x" * 500}"
    @error.update!(message: long_value)
    @error.occurrences.last.update!(context: {url: long_value})

    get solid_errors.error_path(@error)

    assert_select "pre.wrap-anywhere", text: long_value
    assert_select "dd.wrap-anywhere code", text: long_value
    assert_select "h1.wrap-anywhere"
    assert_select "style", text: /\.wrap-anywhere\s*\{\s*overflow-wrap: anywhere/

    get solid_errors.errors_path

    assert_select "td pre.wrap-anywhere", text: long_value
  end

  test "backtrace source scrolls sideways so its lines keep their alignment" do
    occurrence = @error.occurrences.last
    occurrence.update!(backtrace: "#{Rails.root.join("config/routes.rb")}:8:in 'block in <main>'")

    get solid_errors.error_path(@error)

    assert_select "#backtrace-application-#{occurrence.id} pre.overflow-x-auto"
    assert_select "#backtrace-application-#{occurrence.id} summary.wrap-anywhere"
  end

  test "the dashboard links back to the host app's root" do
    get solid_errors.errors_path

    assert_select "main a[href='/']", text: "← Back to main app"
  end

  test "the dashboard renders in apps that do not make English available" do
    available_locales, default_locale, locale = I18n.available_locales, I18n.default_locale, I18n.locale
    I18n.available_locales = [:fr]
    I18n.default_locale = I18n.locale = :fr

    get solid_errors.errors_path
    assert_response :success

    get solid_errors.error_path(@error)
    assert_response :success
  ensure
    I18n.available_locales = available_locales
    I18n.default_locale = default_locale
    I18n.locale = locale
  end

  private

  def report_errors(count)
    count.times do
      raise StandardError, "oof"
    rescue => error
      Rails.error.report(error)
    end
  end

  def create_errors(count, resolved: false)
    count.times do |i|
      error = SolidErrors::Error.create!(
        exception_class: "Err#{i}", message: "msg #{i}", severity: "error", source: "test", fingerprint: "fp#{i}",
        resolved_at: (Time.current if resolved)
      )
      error.occurrences.create!(created_at: i.minutes.ago)
    end
  end

  def pagination_hrefs
    css_select("nav[aria-label=Pages] a[href]").map { |link| link["href"] }
  end
end
