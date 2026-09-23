# frozen_string_literal: true

require "rails/generators"
require "rails/generators/actions"

module RailsXz
  module Generators
    # Installs the audit Engine into the host application:
    #
    #   bin/rails g rails_xz:install
    #
    # It mounts the Engine at /xz_audit in development and test only, so the
    # development-time audit surface never reaches production
    # (docs/03-audit-engine.md §1), and prints the migration step that creates
    # the audit table.
    class InstallGenerator < ::Rails::Generators::Base
      desc "Mount the rails.xz audit Engine and show how to install its migration."

      MOUNT_PATH = "/xz_audit"

      def mount_engine
        route <<~ROUTE
          # rails.xz audit board: renders AI-written Xz modules for human review.
          # Development and test only; the audit surface is development-time
          # tooling. See docs/03-audit-engine.md §1.
          mount RailsXz::Engine => "#{MOUNT_PATH}" if Rails.env.local?
        ROUTE
      end

      def show_migration_steps
        say <<~TEXT

          rails.xz is mounted at #{MOUNT_PATH} in development and test.

          Install the audit table migration, then migrate:

            bin/rails rails_xz:install:migrations
            bin/rails db:migrate

        TEXT
      end
    end
  end
end
