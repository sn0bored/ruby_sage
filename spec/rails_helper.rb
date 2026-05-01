# frozen_string_literal: true

ENV["RAILS_ENV"] ||= "test"

require File.expand_path("dummy/config/environment", __dir__)
require "rspec/rails"

RSpec.configure do |config|
  config.use_transactional_fixtures = false
  config.infer_spec_type_from_file_location!
  config.filter_rails_from_backtrace!

  config.before(:suite) do
    previous_verbosity = ActiveRecord::Migration.verbose
    ActiveRecord::Migration.verbose = false
    ActiveRecord::MigrationContext.new(RubySage::Engine.paths["db/migrate"].to_a).migrate
  ensure
    ActiveRecord::Migration.verbose = previous_verbosity
  end
end
