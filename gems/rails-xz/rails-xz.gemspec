# frozen_string_literal: true

require_relative "lib/rails_xz/version"

Gem::Specification.new do |spec|
  spec.name = "rails-xz"
  spec.version = RailsXz::VERSION
  spec.authors = ["imrubydev"]
  spec.email = ["331856468+imrubydev@users.noreply.github.com"]

  spec.summary = "A Rails Engine for AI-written, human-reviewed Xz modules."
  spec.description = "Mount the audit board, use the Xz::Module service DSL, " \
                     "and approve AI-generated Xz logic from a Rails app."
  spec.homepage = "https://github.com/imrubydev/rails-xz"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir["lib/**/*", "app/**/*", "config/**/*", "db/**/*", "README.md", "LICENSE"]
  spec.require_paths = ["lib"]

  spec.add_dependency "actionpack", ">= 7.1"
  spec.add_dependency "activerecord", ">= 7.1"
  spec.add_dependency "railties", ">= 7.1"
  spec.add_dependency "turbo-rails", ">= 1.5"
  spec.add_dependency "view_component", ">= 3.0"

  spec.add_dependency "rails-xz-agent", "~> 0.1"
  spec.add_dependency "rails-xz-bridge", "~> 0.1"

  spec.add_development_dependency "minitest", "~> 5.0"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "sqlite3", "~> 2.0"
end
