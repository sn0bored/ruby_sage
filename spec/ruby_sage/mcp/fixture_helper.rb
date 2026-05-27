# frozen_string_literal: true

require "fileutils"
require "json"
require "pathname"
require "tmpdir"

require "ruby_sage/artifacts/disk_store"

module RubySageMcpFixtureHelper
  def build_mcp_fixture
    Pathname(Dir.mktmpdir("ruby_sage_mcp_")).tap do |host_root|
      write_host_files(host_root)
      write_manifest(host_root)
      write_artifacts(host_root)
      write_routes(host_root)
    end
  end

  def remove_mcp_fixture(host_root)
    FileUtils.remove_entry(host_root) if host_root&.directory?
  end

  def write_host_files(host_root)
    write_file(host_root, "app/models/user.rb", "class User < ApplicationRecord\n  def active?; true; end\nend\n")
    write_file(host_root, "app/controllers/posts_controller.rb", posts_controller_source)
  end

  def posts_controller_source
    <<~RUBY
      class PostsController < ApplicationController
        def index; end
        def show; end
      end
    RUBY
  end

  def write_file(host_root, relative_path, contents)
    path = host_root.join(relative_path)
    FileUtils.mkdir_p(path.dirname)
    File.write(path, contents)
  end

  def write_manifest(host_root)
    disk_store(host_root).write_manifest(
      attributes: {
        git_sha: "abc123",
        ruby_version: "3.1.2",
        rails_version: "7.1.0",
        started_at: "2026-05-27T12:00:00Z",
        finished_at: "2026-05-27T12:00:30Z",
        file_count: 2,
        scanner: { "include" => ["app"] }
      }
    )
  end

  def write_artifacts(host_root)
    store = disk_store(host_root)
    store.write_artifact(path: "app/models/user.rb", attributes: user_artifact)
    store.write_artifact(path: "app/controllers/posts_controller.rb", attributes: posts_controller_artifact)
  end

  def user_artifact
    {
      kind: "model",
      digest: "user-digest",
      summary: "User account profile and activation state.",
      signature: user_signature,
      public_symbols: ["User", "active?"],
      audiences: ["developer"]
    }
  end

  def user_signature
    {
      classes: [{ name: "User", superclass: "ApplicationRecord", includes: ["Searchable"] }],
      methods: [
        { name: "active?", receiver: "instance", visibility: "public", params: [{ name: "limit", kind: "key" }] }
      ],
      activerecord: { associations: [], validations: [], enums: [], scopes: [] },
      constants: ["MAX_LOGIN_ATTEMPTS"]
    }
  end

  def posts_controller_artifact
    {
      kind: "controller",
      digest: "posts-digest",
      summary: "PostsController lists and displays synthetic posts.",
      signature: {
        classes: [{ name: "PostsController", superclass: "ApplicationController" }],
        methods: [{ name: "index", receiver: "instance", visibility: "public", params: [] }]
      },
      public_symbols: %w[PostsController index],
      audiences: ["developer"]
    }
  end

  def write_routes(host_root)
    path = host_root.join(".ruby_sage", "routes.json")
    File.write(path, "#{JSON.pretty_generate(routes_payload)}\n")
  end

  def routes_payload
    {
      schema_version: 1,
      routes: [
        route("GET", "/posts", "index"),
        route("POST", "/posts", "create"),
        route("GET", "/posts/:id", "show")
      ]
    }
  end

  def route(verb, path, action)
    file = "app/controllers/posts_controller.rb"
    { verb: verb, path: path, controller: "PostsController", action: action, file: file }
  end

  def disk_store(host_root)
    RubySage::Artifacts::DiskStore.new(host_root: host_root)
  end
end
