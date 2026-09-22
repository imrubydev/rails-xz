source "https://rubygems.org"

# Monorepo root. Each gem is also installable on its own.
gem "rails-xz", path: "gems/rails-xz"
gem "rails-xz-bridge", path: "gems/rails-xz-bridge"
gem "rails-xz-agent", path: "gems/rails-xz-agent"

group :development, :test do
  gem "minitest", "~> 5.0"
  gem "rake", "~> 13.0"
  gem "rubocop", "~> 1.60", require: false
end