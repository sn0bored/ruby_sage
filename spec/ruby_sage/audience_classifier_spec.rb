# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubySage::AudienceClassifier do
  let(:config) { RubySage::Configuration.new }

  describe "#call (default heuristic)" do
    {
      "app/services/billing.rb" => %w[developer],
      "app/jobs/charge_card_job.rb" => %w[developer],
      "app/policies/post_policy.rb" => %w[developer],
      "app/queries/recent_posts.rb" => %w[developer],
      "app/workers/sweeper_worker.rb" => %w[developer],
      "app/decorators/user_decorator.rb" => %w[developer],
      "app/serializers/user_serializer.rb" => %w[developer],
      "app/components/button_component.rb" => %w[developer],
      "lib/some_helper.rb" => %w[developer],
      "config/routes.rb" => %w[developer],
      "README.md" => %w[developer],
      "CLAUDE.md" => %w[developer],
      ".cursorrules" => %w[developer],
      "app/models/user.rb" => %w[developer admin],
      "app/controllers/posts_controller.rb" => %w[developer admin],
      "app/views/posts/index.html.erb" => %w[developer admin],
      "app/helpers/post_helper.rb" => %w[developer admin],
      "app/mailers/notification_mailer.rb" => %w[developer admin],
      "db/schema.rb" => %w[developer admin],
      "app/controllers/admin/users_controller.rb" => %w[developer admin],
      "app/views/admin/dashboard.html.erb" => %w[developer admin],
      "app/admin/anything.rb" => %w[developer admin]
    }.each do |path, expected|
      it "tags #{path} as #{expected.inspect}" do
        result = described_class.new(config: config).call(attributes: { path: path })
        expect(result).to eq(expected)
      end
    end

    it "tags unknown paths developer-only" do
      result = described_class.new(config: config).call(attributes: { path: "weird/path/file.rb" })
      expect(result).to eq(%w[developer])
    end
  end

  describe "host overrides" do
    it "honors a config.audience_for callable that returns symbols" do
      config.audience_for = ->(attrs) { %i[user] if attrs[:path].start_with?("docs/") }

      developer_path = described_class.new(config: config).call(attributes: { path: "app/models/user.rb" })
      docs_path = described_class.new(config: config).call(attributes: { path: "docs/help.md" })

      expect(developer_path).to eq(%w[developer admin])
      expect(docs_path).to eq(%w[user])
    end

    it "treats a nil result from audience_for as 'no override' and uses the default" do
      config.audience_for = ->(_attrs) {}
      result = described_class.new(config: config).call(attributes: { path: "app/services/billing.rb" })
      expect(result).to eq(%w[developer])
    end

    it "additively tags user_facing_paths matches with :user" do
      config.user_facing_paths = ["app/views/help/**/*"]
      classifier = described_class.new(config: config)
      help_path = classifier.call(attributes: { path: "app/views/help/getting_started.html.erb" })
      other_view = classifier.call(attributes: { path: "app/views/posts/index.html.erb" })

      expect(help_path).to include("user")
      expect(help_path).to include("developer", "admin")
      expect(other_view).not_to include("user")
    end
  end
end
