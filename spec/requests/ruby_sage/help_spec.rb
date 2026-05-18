# frozen_string_literal: true

require "rails_helper"

RSpec.describe "RubySage help index", type: :request do
  before do
    RubySage.reset_configuration!
    RubySage::KnowledgeChunk.delete_all
  end

  after do
    RubySage.reset_configuration!
    RubySage::KnowledgeChunk.delete_all
  end

  describe "GET /ruby_sage/help" do
    it "returns forbidden without auth" do
      get "/ruby_sage/help"
      expect(response).to have_http_status(:forbidden)
    end

    it "lists published entries" do
      allow_access
      RubySage::KnowledgeChunk.create!(title: "How to export", body: "Step 1.")
      RubySage::KnowledgeChunk.create!(title: "Draft entry", body: "Not yet.", published: false)

      get "/ruby_sage/help"

      expect(response.body).to include("How to export")
      expect(response.body).not_to include("Draft entry")
    end

    it "filters with ?q=…" do
      allow_access
      RubySage::KnowledgeChunk.create!(title: "Monthly report", body: ".")
      RubySage::KnowledgeChunk.create!(title: "User invite", body: ".")

      get "/ruby_sage/help", params: { q: "monthly" }

      expect(response.body).to include("Monthly report")
      expect(response.body).not_to include("User invite")
    end
  end

  describe "GET /ruby_sage/help/:slug" do
    it "renders the markdown body" do
      allow_access
      RubySage::KnowledgeChunk.create!(slug: "report", title: "Report",
                                       body: "## Step 1\n\nDo a thing.")

      get "/ruby_sage/help/report"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Step 1")
    end

    it "404s when the entry is hidden in the configured mode" do
      allow_access
      RubySage.configure { |c| c.mode = :user }
      RubySage::KnowledgeChunk.create!(slug: "admin-only", title: "x", body: ".",
                                       audiences: ["admin"])

      get "/ruby_sage/help/admin-only"

      expect(response).to have_http_status(:not_found)
    end
  end

  def allow_access
    RubySage.configure { |config| config.auth_check = ->(_controller) { true } }
  end
end
