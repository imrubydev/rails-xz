# frozen_string_literal: true

ENV["RAILS_ENV"] ||= "test"
ENV["DATABASE_URL"] ||= "sqlite3::memory:"

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require_relative "dummy/config/environment"
require "rails/test_help"

ActiveRecord::MigrationContext.new(
  RailsXz::Engine.paths["db/migrate"].to_a
).migrate

require "minitest/autorun"
