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

    MARKDOWN_OCCURRENCE_LIMIT = 25

    # Renders the error and its most recent occurrences from the
    # solid_errors/errors/markdown templates, which host apps can override.
    # Rendered as `text` rather than `md` so ActionView's ERB handler skips
    # HTML escaping (its escape_ignore_list covers text/plain).
    def to_markdown(limit: 1)
      # A limit from request params may be an array or hash, such as ?limit[]=5; treat it as the default
      limit = (limit.respond_to?(:to_i) ? limit.to_i : 1).clamp(1, MARKDOWN_OCCURRENCE_LIMIT)
      occurrences = self.occurrences.order(created_at: :desc).limit(limit).to_a

      SolidErrors::ErrorsController.render(
        template: "solid_errors/errors/show",
        formats: [:text],
        layout: false,
        locals: {error: self, occurrences: occurrences}
      )
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
