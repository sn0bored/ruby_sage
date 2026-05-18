# frozen_string_literal: true

require "rails_helper"

RSpec.describe "RubySage admin knowledge", type: :request do
  before do
    RubySage.reset_configuration!
    RubySage::KnowledgeChunk.delete_all
  end

  after do
    RubySage.reset_configuration!
    RubySage::KnowledgeChunk.delete_all
  end

  describe "GET /ruby_sage/admin/knowledge_chunks" do
    it "returns forbidden without auth" do
      get "/ruby_sage/admin/knowledge_chunks"
      expect(response).to have_http_status(:forbidden)
    end

    it "lists entries with auth" do
      allow_access
      RubySage::KnowledgeChunk.create!(title: "Reports", body: "How to.", source: "yaml")

      get "/ruby_sage/admin/knowledge_chunks"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Reports")
      expect(response.body).to include("YAML") # source badge
    end
  end

  describe "POST /ruby_sage/admin/knowledge_chunks" do
    it "creates an admin-sourced entry" do
      allow_access

      post "/ruby_sage/admin/knowledge_chunks", params: {
        knowledge_chunk: {
          title: "My new entry", body: "Body here.",
          tags_string: "alpha, beta", audiences: ["admin"]
        }
      }

      chunk = RubySage::KnowledgeChunk.find_by(slug: "my-new-entry")
      expect(chunk).to be_present
      expect(chunk.source).to eq("admin_ui")
      expect(chunk.tags).to eq(%w[alpha beta])
      expect(chunk.audiences).to eq(%w[admin])
    end

    it "re-renders new on validation error" do
      allow_access

      post "/ruby_sage/admin/knowledge_chunks", params: {
        knowledge_chunk: { title: "", body: "" }
      }

      expect(response).to have_http_status(422)
    end
  end

  describe "PATCH /ruby_sage/admin/knowledge_chunks/:slug" do
    it "refuses to update yaml-sourced rows" do
      allow_access
      RubySage::KnowledgeChunk.create!(slug: "yaml-row", title: "YAML", body: ".", source: "yaml")

      patch "/ruby_sage/admin/knowledge_chunks/yaml-row", params: {
        knowledge_chunk: { title: "Hacked" }
      }

      expect(response).to redirect_to("/ruby_sage/admin/knowledge_chunks/yaml-row")
      expect(RubySage::KnowledgeChunk.find_by(slug: "yaml-row").title).to eq("YAML")
    end

    it "updates admin-sourced rows" do
      allow_access
      RubySage::KnowledgeChunk.create!(slug: "admin-row", title: "Original",
                                       body: ".", source: "admin_ui")

      patch "/ruby_sage/admin/knowledge_chunks/admin-row", params: {
        knowledge_chunk: { title: "Updated", body: "." }
      }

      expect(RubySage::KnowledgeChunk.find_by(slug: "admin-row").title).to eq("Updated")
    end
  end

  describe "DELETE /ruby_sage/admin/knowledge_chunks/:slug" do
    it "refuses to delete yaml-sourced rows" do
      allow_access
      RubySage::KnowledgeChunk.create!(slug: "yaml-row", title: "YAML", body: ".", source: "yaml")

      delete "/ruby_sage/admin/knowledge_chunks/yaml-row"

      expect(RubySage::KnowledgeChunk.find_by(slug: "yaml-row")).to be_present
    end

    it "deletes admin-sourced rows" do
      allow_access
      RubySage::KnowledgeChunk.create!(slug: "admin-row", title: "x", body: ".", source: "admin_ui")

      delete "/ruby_sage/admin/knowledge_chunks/admin-row"

      expect(RubySage::KnowledgeChunk.find_by(slug: "admin-row")).to be_nil
    end
  end

  def allow_access
    RubySage.configure { |config| config.auth_check = ->(_controller) { true } }
  end
end
