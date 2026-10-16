# frozen_string_literal: true

require "rails/generators/active_record/migration"

module SolidErrors
  #
  # Rails generator that writes the migrations an existing SolidErrors install needs after upgrading.
  # Run it with +bin/rails g solid_errors:upgrade+, then +bin/rails db:migrate+.
  #
  class UpgradeGenerator < Rails::Generators::Base
    include ActiveRecord::Generators::Migration

    desc "Write the migrations an existing SolidErrors install needs after upgrading"

    source_root File.expand_path("templates", __dir__)

    class_option :database, type: :string, default: "errors",
      desc: "The database your errors live in; primary when they share the app's database"

    def add_claims_migration
      migration_template "add_solid_errors_claims.rb", File.join(errors_migrate_path, "add_solid_errors_claims.rb")
    end

    private

    # Rails' convention is db/<name>_migrate for every database but the primary
    def errors_migrate_path
      configured_migrate_path ||
        ((options[:database] == "primary") ? "db/migrate" : "db/#{options[:database]}_migrate")
    end
  end
end
