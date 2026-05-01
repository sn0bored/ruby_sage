# frozen_string_literal: true

require "rails_helper"

RSpec.describe "RubySage admin scans", type: :request do
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

  describe "GET /ruby_sage/admin/scans" do
    it "returns forbidden without auth" do
      get "/ruby_sage/admin/scans"

      expect(response).to have_http_status(:forbidden)
    end

    it "returns ok with auth" do
      allow_access

      get "/ruby_sage/admin/scans"

      expect(response).to have_http_status(:ok)
    end

    it "shows scan history" do
      allow_access
      scan = RubySage::Scan.create!(
        status: "completed",
        started_at: 10.seconds.ago,
        finished_at: Time.current,
        file_count: 42,
        ruby_version: "3.3.4",
        rails_version: "7.2.0",
        git_sha: "abc1234def5678"
      )

      get "/ruby_sage/admin/scans"

      expect(response.body).to include(scan.status)
      expect(response.body).to include("42")
      expect(response.body).to include("abc1234")
    end

    it "shows artifact counts broken down by kind when a completed scan exists" do
      allow_access
      scan = RubySage::Scan.create!(status: "completed", finished_at: Time.current, file_count: 2)
      RubySage::Artifact.create!(scan: scan, path: "app/models/post.rb", kind: "model",
                                 digest: "aaa", summary: "Post model")
      RubySage::Artifact.create!(scan: scan, path: "app/controllers/posts_controller.rb",
                                 kind: "controller", digest: "bbb", summary: "Posts controller")

      get "/ruby_sage/admin/scans"

      expect(response.body).to include("model")
      expect(response.body).to include("controller")
    end

    it "shows an empty state message when there are no scans" do
      allow_access

      get "/ruby_sage/admin/scans"

      expect(response.body).to include("No scans yet")
    end
  end

  describe "POST /ruby_sage/admin/scans" do
    it "returns forbidden without auth" do
      post "/ruby_sage/admin/scans"

      expect(response).to have_http_status(:forbidden)
    end

    it "triggers a scan and redirects" do
      allow_access
      allow(RubySage::Scanner).to receive(:new).and_return(
        instance_double(RubySage::Scanner, run: nil)
      )

      post "/ruby_sage/admin/scans"

      expect(response).to redirect_to("/ruby_sage/admin/scans")
    end
  end

  def allow_access
    RubySage.configure { |config| config.auth_check = ->(_controller) { true } }
  end
end
