# frozen_string_literal: true

source "https://rubygems.org"

gemspec

# CI matrix pins a specific Rails minor via RAILS_VERSION (see .github/workflows/ci.yml).
# Locally, leave RAILS_VERSION unset to use whatever Rails the lockfile resolved to.
if (rails_version = ENV.fetch("RAILS_VERSION", nil))
  gem "rails", "~> #{rails_version}.0"
end

group :development, :test do
  gem "puma"
  gem "rspec-rails"
  gem "rubocop"
  gem "rubocop-rails"
  gem "rubocop-rspec"
  gem "sqlite3"
end
