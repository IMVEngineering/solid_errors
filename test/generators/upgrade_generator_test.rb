require "test_helper"
require "rails/generators/test_case"
require "generators/solid_errors/upgrade/upgrade_generator"

class SolidErrors::UpgradeGeneratorTest < Rails::Generators::TestCase
  tests SolidErrors::UpgradeGenerator
  destination File.expand_path("../../tmp/generators", __dir__)
  setup :prepare_destination

  test "writes the claims migration to the errors database's migrations by default" do
    run_generator

    assert_migration "db/errors_migrate/add_solid_errors_claims.rb" do |migration|
      assert_match "class AddSolidErrorsClaims < ActiveRecord::Migration[#{ActiveRecord::Migration.current_version}]", migration
      assert_match "add_column :solid_errors, :claimed_by_id, :string", migration
      assert_match "create_table :solid_errors_events", migration
    end
  end

  test "writes to another database's migrations with --database" do
    run_generator %w[--database primary]

    assert_migration "db/migrate/add_solid_errors_claims.rb"
  end
end
