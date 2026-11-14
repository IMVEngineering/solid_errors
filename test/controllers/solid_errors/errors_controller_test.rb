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

  test "search matches the exception class, message or source" do
    make_error("Billing::Timeout", "card declined", source: "stripe")
    make_error("Other", "nothing", source: "sidekiq")

    {"billing::time" => 1, "DECLINED" => 1, "STRIPE" => 1, "zzz" => 0}.each do |q, count|
      get solid_errors.errors_path(q: q)
      assert_select "tbody tr", count: count
    end
  end

  test "search treats LIKE wildcards literally" do
    make_error("Percent", "100% done")
    make_error("Under", "a_b")
    make_error("Plain", "axb")

    get solid_errors.errors_path(q: "100%")
    assert_select "tbody tr", count: 1
    get solid_errors.errors_path(q: "a_b")
    assert_select "tbody tr", count: 1
    get solid_errors.errors_path(q: "%")
    assert_select "tbody tr", count: 1
  end

  test "a blank search is ignored" do
    get solid_errors.errors_path(q: "  ")

    assert_select "tbody tr", count: 1
    assert_select "a", text: "Clear", count: 0
  end

  test "filters by severity and source and combines with search and scope" do
    make_error("A", "one", severity: "info", source: "web")
    make_error("B", "two", severity: "info", source: "job")
    make_error("C", "three", severity: "error", source: "web", resolved: true)

    get solid_errors.errors_path(severity: "info")
    assert_select "tbody tr", count: 2
    get solid_errors.errors_path(source: "web")
    assert_select "tbody tr", count: 1
    get solid_errors.errors_path(severity: "info", source: "web", q: "one")
    assert_select "tbody tr", count: 1
    get solid_errors.errors_path(source: "web", scope: :resolved)
    assert_select "tbody tr", count: 1
    assert_select "tbody tr", text: /three/
  end

  test "the form offers the values present in the errors table" do
    make_error("A", "one", severity: "info", source: "web")
    get solid_errors.errors_path(severity: "info", scope: :resolved)

    assert_select "form[method=get][action=?]", solid_errors.errors_path
    assert_select "form input[type=hidden][name=scope][value=resolved]"
    assert_select "form select[name=severity] option", count: 3 # All, info, plus the setup error's severity
    assert_select "form select[name=severity] option[selected][value=info]"
    assert_select "form select[name=source] option[value=web]"
    assert_select "form select[name=sort] option", count: 3
    assert_select "form button[type=submit]", text: "Filter"
  end

  test "sorts by last seen, first seen or occurrence count" do
    old_busy = make_error("OldBusy", "x", created_at: 3.days.ago, occurrences: [2.days.ago, 2.hours.ago, 3.hours.ago])
    new_quiet = make_error("NewQuiet", "x", created_at: 1.day.ago, occurrences: [1.minute.ago])
    mid = make_error("Mid", "x", created_at: 2.days.ago, occurrences: [1.hour.ago, 2.days.ago])
    ids = ->(sort) {
      get solid_errors.errors_path(q: "x", sort: sort)
      css_select("tbody tr a[href]").map { |a| a["href"][/\d+\z/].to_i }
    }

    assert_equal [new_quiet, mid, old_busy].map(&:id), ids.call("last_seen")
    assert_equal [new_quiet, mid, old_busy].map(&:id), ids.call(nil)
    assert_equal [new_quiet, mid, old_busy].map(&:id), ids.call("first_seen")
    assert_equal [old_busy, mid, new_quiet].map(&:id), ids.call("occurrences")
    assert_equal [new_quiet, mid, old_busy].map(&:id), ids.call("bogus")
  end

  test "ties sort by newest error first" do
    a = make_error("A", "x", occurrences: [1.day.ago])
    b = make_error("B", "x", occurrences: [1.day.ago])
    get solid_errors.errors_path(q: "x", sort: "occurrences")

    assert_equal [b, a].map { |e| solid_errors.error_path(e) }, css_select("tbody tr a[href]").map { |link| link["href"] }
  end

  test "the pager and tabs keep the search, filters and sort" do
    create_errors(30)
    kept = {q: "msg", severity: "error", source: "test", sort: "occurrences"}
    get solid_errors.errors_path(kept.merge(page: 1))

    assert_includes pagination_hrefs, solid_errors.errors_path(kept.merge(page: 2))
    assert_select "nav[aria-label=Tabs] a[href=?]", solid_errors.errors_path(kept.merge(scope: :resolved))
    assert_select "nav[aria-label=Tabs] a[href=?]", solid_errors.errors_path(kept.merge(scope: :unresolved))
  end

  test "counts and pages reflect the filtered set" do
    create_errors(30)
    make_error("Special", "needle")
    get solid_errors.errors_path(q: "needle")

    assert_select "tbody tr", count: 1
    assert_select "nav[aria-label=Pages]", count: 0

    get solid_errors.errors_path(q: "msg", items: 10)
    assert_select "strong", text: "1-10"
    assert_select "strong", text: "30"
  end

  test "Clear appears only when a search, filter or sort is set" do
    get solid_errors.errors_path
    assert_select "form a", text: "Clear", count: 0

    get solid_errors.errors_path(sort: "occurrences", scope: :resolved)
    assert_select "form a[href=?]", solid_errors.errors_path(scope: :resolved), text: "Clear"
  end

  test "an empty filtered list says so and offers Clear" do
    get solid_errors.errors_path(q: "nothing like this")

    assert_select "tbody", count: 0
    assert_select "p", text: /No errors match these filters\./
    assert_select "p a[href=?]", solid_errors.errors_path(scope: :unresolved), text: "Clear"
  end

  test "an empty list without filters says so plainly" do
    get solid_errors.errors_path(scope: :resolved)

    assert_select "p", text: /No resolved errors\./
  end

  test "array params do not break search" do
    get solid_errors.errors_path, params: {q: ["a"], severity: {x: 1}}

    assert_response :success
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

  test "index renders row checkboxes tied to the bulk resolve form" do
    get solid_errors.errors_path

    assert_select "form#bulk-form[action=?]", solid_errors.resolve_errors_path do
      assert_select "input[name=_method][value=patch]"
      assert_select "button", text: "Resolve selected"
    end
    assert_select "tbody input[type=checkbox][form=bulk-form][name='ids[]']", count: SolidErrors::Error.unresolved.count
    assert_select "thead input[type=checkbox][data-select-all][aria-label]"
    assert_select "button", text: "Delete selected", count: 0
  end

  test "resolved tab renders the bulk delete form" do
    make_error("OldError", "gone", resolved: true)
    get solid_errors.errors_path(scope: :resolved)

    assert_select "form#bulk-form[action=?]", solid_errors.destroy_many_errors_path do
      assert_select "input[name=_method][value=delete]"
      assert_select "button", text: "Delete selected"
    end
    assert_select "tbody input[type=checkbox][form=bulk-form][name='ids[]']", count: 1
    assert_select "button", text: "Resolve selected", count: 0
  end

  test "bulk form carries only the set filter params" do
    make_error("Zork", "zork")
    get solid_errors.errors_path(q: "Zork", severity: "error", sort: "occurrences", page: "1", items: "10")

    assert_select "form#bulk-form" do
      assert_select "input[type=hidden][name=scope][value=unresolved]"
      assert_select "input[type=hidden][name=q][value=Zork]"
      assert_select "input[type=hidden][name=severity][value=error]"
      assert_select "input[type=hidden][name=sort][value=occurrences]"
      assert_select "input[type=hidden][name=page][value='1']"
      assert_select "input[type=hidden][name=items][value='10']"
      assert_select "input[type=hidden][name=source]", count: 0
    end
  end

  test "bulk resolve resolves only the selected errors" do
    a = make_error("A", "a")
    b = make_error("B", "b")
    c = make_error("C", "c")

    patch solid_errors.resolve_errors_path, params: {ids: [a.id, b.id]}

    assert a.reload.resolved?
    assert b.reload.resolved?
    assert_not c.reload.resolved?
    assert_equal "Resolved 2 errors.", flash[:notice]
  end

  test "bulk resolve notifies once per error" do
    a = make_error("A", "a")
    b = make_error("B", "b")
    ids = []
    subscriber = ActiveSupport::Notifications.subscribe("error_resolved.solid_errors") { |*args| ids << args.last[:error].id }

    patch solid_errors.resolve_errors_path, params: {ids: [a.id, b.id]}

    assert_equal [a.id, b.id].sort, ids.sort
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
  end

  test "bulk resolve pluralizes and redirects back with the list state" do
    a = make_error("A", "a")

    patch solid_errors.resolve_errors_path, params: {ids: [a.id], scope: "unresolved", q: "A", severity: "error", source: "test", sort: "occurrences", page: "2", items: "5", evil: "x"}

    assert_equal "Resolved 1 error.", flash[:notice]
    assert_redirected_to solid_errors.errors_path(scope: "unresolved", q: "A", severity: "error", source: "test", sort: "occurrences", page: "2", items: "5")
  end

  test "bulk resolve without a selection redirects with an alert" do
    patch solid_errors.resolve_errors_path, params: {q: "x"}

    assert_redirected_to solid_errors.errors_path(q: "x")
    assert_equal "No errors selected.", flash[:alert]
  end

  test "bulk delete removes only resolved selected errors and their occurrences" do
    resolved = make_error("R", "r", resolved: true, occurrences: [Time.current, 1.hour.ago])
    unresolved = make_error("U", "u")
    untouched = make_error("V", "v", resolved: true)

    delete solid_errors.destroy_many_errors_path, params: {ids: [resolved.id, unresolved.id], scope: "resolved"}

    assert_not SolidErrors::Error.exists?(resolved.id)
    assert_equal 0, SolidErrors::Occurrence.where(error_id: resolved.id).count
    assert SolidErrors::Error.exists?(unresolved.id)
    assert SolidErrors::Error.exists?(untouched.id)
    assert_equal "Deleted 1 error.", flash[:notice]
    assert_redirected_to solid_errors.errors_path(scope: "resolved")
  end

  test "bulk delete without a selection redirects with an alert" do
    delete solid_errors.destroy_many_errors_path, params: {scope: "resolved"}

    assert_redirected_to solid_errors.errors_path(scope: "resolved")
    assert_equal "No errors selected.", flash[:alert]
  end

  test "bulk routes do not collide with show" do
    get "/resolve"
    assert_response :not_found
  end

  def make_error(exception_class, message, severity: "error", source: "test", resolved: false, created_at: Time.current, occurrences: [Time.current])
    error = SolidErrors::Error.create!(
      exception_class: exception_class, message: message, severity: severity, source: source,
      fingerprint: "fp-#{exception_class}-#{message}", created_at: created_at, resolved_at: (Time.current if resolved)
    )
    occurrences.each { |time| error.occurrences.create!(created_at: time) }
    error
  end

  def pagination_hrefs
    css_select("nav[aria-label=Pages] a[href]").map { |link| link["href"] }
  end
end
