# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubySage::WidgetHelper, type: :helper do
  before { RubySage.reset_configuration! }

  after { RubySage.reset_configuration! }

  describe "#ruby_sage_widget" do
    it "returns an empty string when the scope check fails" do
      expect(helper.ruby_sage_widget).to eq("")
    end

    it "renders the widget partial when the scope allows it" do
      RubySage.configure { |config| config.scope = :public_rate_limited }
      allow(helper).to receive(:render).with(partial: "ruby_sage/widget/widget").and_return("rendered")

      expect(helper.ruby_sage_widget).to eq("rendered")
    end
  end

  describe "#ruby_sage_csp_nonce" do
    it "returns nil when no nonce callable is configured" do
      expect(helper.ruby_sage_csp_nonce).to be_nil
    end

    it "returns the configured nonce callable result" do
      RubySage.configure { |config| config.csp_nonce = ->(_view_context) { "nonce-value" } }

      expect(helper.ruby_sage_csp_nonce).to eq("nonce-value")
    end
  end
end
