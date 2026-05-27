# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubySage::Extractors::RoutesLoader do
  let(:routes_path) { Rails.root.join(".ruby_sage/routes.json") }

  before { cleanup_routes_artifact }

  after { cleanup_routes_artifact }

  def cleanup_routes_artifact
    FileUtils.rm_f(routes_path)
    routes_path.dirname.rmdir if routes_path.dirname.directory? && routes_path.dirname.children.empty?
  end

  it "writes application routes to disk and skips Rails internals" do
    written_path = described_class.new(host_root: Rails.root).run
    payload = JSON.parse(routes_path.read)

    expect(written_path).to eq(routes_path)
    expect(payload["schema_version"]).to eq(1)
    expect(payload["routes"]).to include(
      "verb" => "GET",
      "path" => "/posts",
      "controller" => "PostsController",
      "action" => "index",
      "file" => "app/controllers/posts_controller.rb",
      "name" => "posts"
    )
    expect(payload["routes"].pluck("path")).not_to include(a_string_starting_with("/rails"))
  end
end
