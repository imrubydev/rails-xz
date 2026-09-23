# frozen_string_literal: true

require "test_helper"
require "generators/rails_xz/install/install_generator"
require "rails/generators/test_case"

class InstallGeneratorTest < Rails::Generators::TestCase
  tests RailsXz::Generators::InstallGenerator
  destination File.expand_path("tmp/install_generator", __dir__)

  setup do
    prepare_destination
    mkdir_p(File.join(destination_root, "config"))
    File.write(File.join(destination_root, "config", "routes.rb"), <<~ROUTES)
      Rails.application.routes.draw do
      end
    ROUTES
  end

  teardown do
    rm_rf(destination_root)
  end

  test "mounts the engine guarded to development and test" do
    run_generator

    assert_file "config/routes.rb" do |routes|
      assert_match(
        %(mount RailsXz::Engine => "/xz_audit" if Rails.env.local?),
        routes
      )
    end
  end

  test "tells the developer how to install the audit table migration" do
    output = run_generator

    assert_match "rails_xz:install:migrations", output
    assert_match "db:migrate", output
  end
end
