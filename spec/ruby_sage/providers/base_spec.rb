# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubySage::Providers::Base do
  subject(:provider) { described_class.new(RubySage.configuration) }

  before { RubySage.reset_configuration! }

  it "requires subclasses to implement chat" do
    expect do
      provider.chat(system_prompt: "system", cached_context: nil, messages: [])
    end.to raise_error(NotImplementedError)
  end
end
