module SolidErrors
  # Something someone did to an error: claimed, unclaimed, resolved or reopened it
  class Event < Record
    self.table_name = "solid_errors_events"

    ACTIONS = %w[claimed unclaimed resolved reopened].freeze

    belongs_to :error, class_name: "SolidErrors::Error"

    validates :action, inclusion: {in: ACTIONS}

    def actor=(actor)
      self.actor_id, self.actor_name = actor&.values_at(:id, :name)
    end

    def assignee=(assignee)
      self.assignee_id, self.assignee_name = assignee&.values_at(:id, :name)
    end

    def description
      case action
      when "claimed"
        (actor_id.nil? || actor_id == assignee_id) ? "Claimed by #{assignee_name}" : "Assigned to #{assignee_name} by #{actor_name}"
      when "unclaimed" then by("Unclaimed")
      when "resolved" then by("Resolved")
      when "reopened" then actor_name ? by("Reopened") : "Reopened by a new occurrence"
      end
    end

    private

    def by(verb)
      actor_name ? "#{verb} by #{actor_name}" : verb
    end
  end
end
