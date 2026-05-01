# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubySage do
  it "has a version number" do
    expect(RubySage::VERSION).not_to be_nil
  end
end
