# frozen_string_literal: true

require "rails"
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "action_controller/railtie"
require "action_view/railtie"
require "rails/test_unit/railtie"

require "rails_xz"

# A minimal host application that mounts the audit Engine so the gem can run
# integration tests without a generated app. See docs/07-dev-environment.md.
module Dummy
  class Application < Rails::Application
    config.load_defaults Rails::VERSION::STRING.to_f
    config.eager_load = false
    config.root = File.expand_path("..", __dir__)
    config.secret_key_base = "rails-xz-test-secret-key-base"
    config.hosts.clear
    config.active_record.default_timezone = :utc
    config.active_record.maintain_test_schema = false
    config.action_controller.allow_forgery_protection = false
    config.action_dispatch.show_exceptions = :none
  end
end
