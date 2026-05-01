# frozen_string_literal: true

require "rails_helper"

RSpec.describe "RubySage admin artifacts", type: :request do
  before do
    RubySage.reset_configuration!
    RubySage::Artifact.delete_all
    RubySage::Scan.delete_all
  end

  after do
    RubySage.reset_configuration!
    RubySage::Artifact.delete_all
    RubySage::Scan.delete_all
  end

  describe "GET /ruby_sage/admin/artifacts" do
    it "returns forbidden without auth" do
      get "/ruby_sage/admin/artifacts"

      expect(response).to have_http_status(:forbidden)
    end

    it "shows an empty state when no scan exists" do
      allow_access

      get "/ruby_sage/admin/artifacts"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("No completed scan found")
    end

    it "lists artifacts from the latest completed scan" do
      allow_access
      seed_scan_with_artifacts

      get "/ruby_sage/admin/artifacts"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("app/models/post.rb")
      expect(response.body).to include("A Post represents a published article")
    end

    it "filters by kind" do
      allow_access
      seed_scan_with_artifacts

      get "/ruby_sage/admin/artifacts", params: { kind: "model" }

      expect(response.body).to include("app/models/post.rb")
      expect(response.body).not_to include("app/controllers/posts_controller.rb")
    end
  end

  def allow_access
    RubySage.configure { |config| config.auth_check = ->(_controller) { true } }
  end

  def seed_scan_with_artifacts
    scan = RubySage::Scan.create!(status: "completed", finished_at: Time.current, file_count: 2)
    RubySage::Artifact.create!(
      scan: scan, path: "app/models/post.rb", kind: "model",
      digest: "aaa", summary: "A Post represents a published article.",
      public_symbols: ["Post"]
    )
    RubySage::Artifact.create!(
      scan: scan, path: "app/controllers/posts_controller.rb", kind: "controller",
      digest: "bbb", summary: "PostsController handles CRUD for posts.",
      public_symbols: ["PostsController#index", "PostsController#show"]
    )
    scan
  end
end
