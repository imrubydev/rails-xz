# frozen_string_literal: true

require_relative "lib/rails_xz/bridge/version"

Gem::Specification.new do |spec|
  spec.name = "rails-xz-bridge"
  spec.version = RailsXz::Bridge::VERSION
  spec.authors = ["ax1s-x1zz"]
  spec.email = ["261901424+ax1s-x1zz@users.noreply.github.com"]

  spec.summary = "Ruby FFI bridge for Xz shared libraries."
  spec.description = "Generate Ruby bindings from .xzint interfaces and load " \
                     "compiled Xz shared libraries through Fiddle or ffi."
  spec.homepage = "https://github.com/imrubydev/rails-xz"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir["lib/**/*", "README.md", "LICENSE"]
  spec.require_paths = ["lib"]

  # By-value aggregates (Str/Bytes/@cstruct) need the ffi gem; Fiddle cannot
  # pass or return a C struct by value. Scalar- and pointer-only calls still use
  # Fiddle, which ships with Ruby. See docs/01-bridge.md section 3.
  spec.add_dependency "ffi", "~> 1.15"

  spec.add_development_dependency "minitest", "~> 5.0"
  spec.add_development_dependency "rake", "~> 13.0"
end