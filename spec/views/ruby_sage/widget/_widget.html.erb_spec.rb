# frozen_string_literal: true

require "rails_helper"

RSpec.describe "ruby_sage/widget/_widget", type: :view do
  before { RubySage.reset_configuration! }

  after { RubySage.reset_configuration! }

  it "renders the widget root with the mount data attribute" do
    render partial: "ruby_sage/widget/widget"

    expect(rendered).to include('id="ruby-sage-root"').and include('data-mount="/ruby_sage"')
  end

  it "includes the widget stylesheet and javascript assets" do
    render partial: "ruby_sage/widget/widget"

    expect(rendered)
      .to include("ruby_sage/widget.css")
      .and include("ruby_sage/widget.js")
      .and include('data-turbo-track="reload"')
  end

  it "includes a nonce attribute on the script tag when configured" do
    RubySage.configure { |config| config.csp_nonce = ->(_view_context) { "nonce-value" } }

    render partial: "ruby_sage/widget/widget"

    expect(rendered).to include('nonce="nonce-value"')
  end
end
