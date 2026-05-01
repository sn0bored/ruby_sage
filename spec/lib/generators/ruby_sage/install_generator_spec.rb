# frozen_string_literal: true

require "rails_helper"
require "rails/generators"
require "rails/generators/test_case"
require "generators/ruby_sage/install/install_generator"

RSpec.describe RubySage::Generators::InstallGenerator, type: :generator do
  destination = File.expand_path("../../../../tmp/generator_destination", __dir__)

  before do
    FileUtils.rm_rf(destination)
    FileUtils.mkdir_p(destination)
    # The install_migrations step shells out to a host-app rake task that does
    # not exist inside the gem's test sandbox. Stub it so the spec focuses on
    # the file the generator writes.
    allow_any_instance_of(described_class).to receive(:install_migrations)
  end

  after do
    FileUtils.rm_rf(destination)
  end

  it "copies the configuration initializer" do
    silence_stdout do
      described_class.start([], destination_root: destination)
    end

    initializer = File.join(destination, "config/initializers/ruby_sage.rb")
    expect(File).to exist(initializer)

    contents = File.read(initializer)
    expect(contents).to include("RubySage.configure")
    expect(contents).to include(":anthropic")
    expect(contents).to include("ANTHROPIC_API_KEY")
  end

  def silence_stdout
    original = $stdout
    $stdout = StringIO.new
    yield
  ensure
    $stdout = original
  end
end
