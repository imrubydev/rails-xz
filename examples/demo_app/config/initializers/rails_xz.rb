# frozen_string_literal: true

# Bindings live under lib/ so config.autoload_lib resolves
# Xz::Bindings::<Stem> through Zeitwerk (docs/03-audit-engine.md section 8).
# git_identity is required for the one-click approval commit; the Engine never
# falls back to the machine's global git identity.
RailsXz.configure do |config|
  config.bindings_root = "lib/xz/bindings"
  config.build_root = "vendor/xz"
  config.git_identity = {
    name: ENV.fetch("RAILS_XZ_GIT_NAME", "Demo Developer"),
    email: ENV.fetch("RAILS_XZ_GIT_EMAIL", "demo@example.com")
  }
end
