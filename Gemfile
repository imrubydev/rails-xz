source "https://rubygems.org"

# Monorepo root. Each gem is also installable on its own.
gem "rails-xz", path: "gems/rails-xz"
gem "rails-xz-bridge", path: "gems/rails-xz-bridge"
gem "rails-xz-agent", path: "gems/rails-xz-agent"

group :development, :test do
  gem "minitest", "~> 5.0"
  gem "rake", "~> 13.0"
  gem "rubocop", "~> 1.60", require: false

  # Test dependencies of the Engine. Path gems do not pull in a dependency's
  # development dependencies, so the aggregator must declare them itself.
  gem "sqlite3", "~> 2.0"

  # json 3.x dropped the positional options hash that ActiveSupport 8.1 still
  # passes to JSON.parse; pin to 2.x until Rails has a compatible release.
  gem "json", "~> 2.9"
end