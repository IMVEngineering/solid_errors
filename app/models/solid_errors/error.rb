module SolidErrors
  class Error < Record
    self.table_name = "solid_errors"

    SEVERITY_TO_EMOJI = {
      error: "🔥",
      warning: "⚠️",
      info: "ℹ️"
    }
    SEVERITY_TO_BADGE_CLASSES = {
      error: "bg-red-100 text-red-800",
      warning: "bg-yellow-100 text-yellow-800",
      info: "bg-blue-100 text-blue-800"
    }
    STATUS_TO_EMOJI = {
      resolved: "✅",
      unresolved: "⏳"
    }
    STATUS_TO_BADGE_CLASSES = {
      resolved: "bg-green-100 text-green-800",
      unresolved: "bg-violet-100 text-violet-800"
    }

    has_many :occurrences, class_name: "SolidErrors::Occurrence", dependent: :destroy
    # Not dependent: :delete_all, which would query the events table in apps that haven't added it
    has_many :events, class_name: "SolidErrors::Event"

    # Who resolved or reopened the error in this update, as {id:, name:}; nil for a new occurrence
    attr_accessor :resolving_actor

    validates :exception_class, presence: true
    validates :message, presence: true
    validates :severity, presence: true

    scope :resolved, -> { where.not(resolved_at: nil) }
    scope :unresolved, -> { where(resolved_at: nil) }

    before_update :clear_claim, if: -> { will_save_change_to_resolved_at? && resolved? && SolidErrors.claiming_migrated? }
    after_update :record_resolution_event, if: -> { saved_change_to_resolved_at? && SolidErrors.claiming? }
    before_destroy :destroy_events, if: -> { SolidErrors.claiming_migrated? }
    after_update_commit :publish_resolved, if: -> { saved_change_to_resolved_at? && resolved? }

    def severity_emoji
      SEVERITY_TO_EMOJI[severity.to_sym]
    end

    def severity_badge_classes
      "px-2 inline-flex text-sm font-semibold rounded-md #{SEVERITY_TO_BADGE_CLASSES[severity.to_sym]}"
    end

    def status
      resolved? ? :resolved : :unresolved
    end

    def status_emoji
      STATUS_TO_EMOJI[status]
    end

    def status_badge_classes
      "px-2 inline-flex text-sm font-semibold rounded-md #{STATUS_TO_BADGE_CLASSES[status]}"
    end

    def resolved?
      resolved_at.present?
    end

    def claimed?
      claimed_by_id.present?
    end

    # Claim the error for assignee, as {id:, name:}; actor is who did it
    def claim!(assignee:, actor: nil)
      transaction do
        update!(claimed_by_id: assignee[:id], claimed_by_name: assignee[:name])
        events.create!(action: "claimed", actor: actor, assignee: assignee)
      end
      ActiveSupport::Notifications.instrument("error_claimed.solid_errors", error: self, actor: actor, assignee: assignee)
    end

    def unclaim!(actor: nil)
      assignee = claimed? ? {id: claimed_by_id, name: claimed_by_name} : nil
      transaction do
        update!(claimed_by_id: nil, claimed_by_name: nil)
        events.create!(action: "unclaimed", actor: actor, assignee: assignee)
      end
      ActiveSupport::Notifications.instrument("error_unclaimed.solid_errors", error: self, actor: actor, assignee: assignee)
    end

    def to_markdown
      md = ""
      md << "## Exception: #{exception_class}\n"
      md << "**Severity:** #{severity} | **Source:** #{source}\n\n"
      md << "### Message\n#{message}\n"

      occurrence = occurrences.order(created_at: :desc).first
      return md unless occurrence

      backtrace = occurrence.parsed_backtrace

      md << "\n### Backtrace\n"
      backtrace.lines.each do |line|
        md << (line.filtered_method ? line.to_s : line.unparsed_line) << "\n"
      end

      app_lines = backtrace.application_lines
      if app_lines.any?
        md << "\n### Source Context\n"
        app_lines.each do |line|
          md << "#### #{line}\n"
          md << "```ruby\n"
          line.source.each { |n, code| md << "#{n}: #{code.chomp}\n" }
          md << "```\n\n"
        end
      end

      if occurrence.context.present?
        md << "### Request Context\n"
        occurrence.context.each { |k, v| md << "- #{k}: #{v}\n" }
      end

      md
    end

    private

    def publish_resolved
      ActiveSupport::Notifications.instrument("error_resolved.solid_errors", error: self, actor: resolving_actor)
    end

    def clear_claim
      self.claimed_by_id = self.claimed_by_name = nil
    end

    def record_resolution_event
      events.create!(action: resolved? ? "resolved" : "reopened", actor: resolving_actor)
    end

    def destroy_events
      SolidErrors::Event.where(error_id: id).delete_all
    end
  end
end
