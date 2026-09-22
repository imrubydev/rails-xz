# frozen_string_literal: true

require "rails/engine"

module RailsXz
  # The mountable audit Engine.
  #
  #   # config/routes.rb (host app)
  #   mount RailsXz::Engine => "/xz_audit"
  #
  # The Engine is isolated: its own namespace, tables, routes, controllers, and
  # views. It does not reopen host application classes.
  class Engine < ::Rails::Engine
    isolate_namespace RailsXz

    config.generators do |g|
      g.test_framework :minitest, fixture: false
    end
  end
end