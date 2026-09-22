# frozen_string_literal: true

require_relative "lib/rails_xz/agent/version"

Gem::Specification.new do |spec|
  spec.name = "rails-xz-agent"
  spec.version = RailsXz::Agent::VERSION
  spec.authors = ["ax1s-x1zz", "imrubydev"]
  spec.email = ["261901424+ax1s-x1zz@users.noreply.github.com",
                "331856468+imrubydev@users.noreply.github.com"]

  spec.summary = "Agent self-correction loop for rails.xz."
  spec.description = "Drive an LLM through xz check-json diagnostics with a " \
                     "bounded retry budget, on ActiveJob."
  spec.homepage = "https://github.com/imrubydev/rails-xz"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir["lib/**/*", "README.md", "LICENSE"]
  spec.require_paths = ["lib"]

  spec.add_dependency "activejob", ">= 7.1"
  spec.add_dependency "rails-xz-bridge", "~> 0.1"

  spec.add_development_dependency "minitest", "~> 5.0"
  spec.add_development_dependency "rake", "~> 13.0"
end