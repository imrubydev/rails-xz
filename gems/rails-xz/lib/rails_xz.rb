# frozen_string_literal: true

require "rails_xz/version"
require "view_component"
require "turbo-rails"
require "rails-xz-bridge"
require "rails-xz-agent"
require "rails_xz/engine"
require "rails_xz/unified_diff"
require "rails_xz/xz_module"
require "rails_xz/approval"

# rails.xz — a Rails Engine for AI-written, human-reviewed Xz modules.
#
# See docs/03-audit-engine.md for the Engine and docs/01-bridge.md for the FFI
# bridge it calls into.
module RailsXz
  # Host-app configuration, set in an initializer:
  #
  #   RailsXz.configure do |config|
  #     config.bindings_root = "app/xz/bindings"
  #     config.build_root = "vendor/xz"
  #     config.git_identity = { name: "Dev", email: "dev@example.com" }
  #   end
  #
  # `git_identity` is required for the P1 approval commit; leaving it unset makes
  # approval fail rather than fall back to the machine's global git identity.
  class Configuration
    attr_accessor :bindings_root, :build_root, :git_identity

    def initialize
      @bindings_root = "app/xz/bindings"
      @build_root = "vendor/xz"
      @git_identity = nil
    end
  end

  class << self
    def config
      @config ||= Configuration.new
    end

    def configure
      yield config
    end

    # Restores the defaults; used by the Engine's own tests.
    def reset_config!
      @config = Configuration.new
    end
  end
end