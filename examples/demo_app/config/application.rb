# frozen_string_literal: true

require_relative "boot"

require "rails"
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "action_controller/railtie"
require "action_view/railtie"
require "rails/test_unit/railtie"

Bundler.require(*Rails.groups)

module DemoApp
  class Application < Rails::Application
    config.load_defaults Rails::VERSION::STRING.to_f

    # Maps lib/xz/bindings/order.rb to Xz::Bindings::Order
    # (docs/03-audit-engine.md section 8).
    config.autoload_lib(ignore: %w[assets tasks])

    config.active_record.default_timezone = :utc
    config.time_zone = "UTC"
  end
end
