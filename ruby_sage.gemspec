# frozen_string_literal: true

require_relative "lib/ruby_sage/version"

Gem::Specification.new do |spec|
  spec.name = "ruby_sage"
  spec.version = RubySage::VERSION
  spec.authors = ["Daniel Willems"]
  spec.email = ["dmkwillems@gmail.com"]

  spec.summary = "Chat with your Rails codebase"
  spec.description = "RubySage is a Rails engine that lets developers chat with their own codebase. " \
                     "It scans the host app, builds per-file artifacts with summaries, and serves a " \
                     "floating chat widget that answers questions with citations."
  spec.homepage = "https://github.com/sn0bored/ruby_sage"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 2.7"

  spec.metadata = {
    "source_code_uri" => "https://github.com/sn0bored/ruby_sage",
    "changelog_uri" => "https://github.com/sn0bored/ruby_sage/blob/main/CHANGELOG.md",
    "rubygems_mfa_required" => "true"
  }

  spec.files = Dir.chdir(__dir__) do
    Dir.glob(
      ["{app,config,db,lib}/**/*", "MIT-LICENSE", "LICENSE", "README.md", "CHANGELOG.md", "Rakefile"],
      File::FNM_DOTMATCH
    ).select { |file| File.file?(file) }
  end
  spec.require_paths = ["lib"]

  spec.add_dependency "rails", ">= 5.2", "< 9.0"
end
