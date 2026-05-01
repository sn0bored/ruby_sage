# frozen_string_literal: true

require "rails_helper"

RSpec.describe "RubySage widget smoke", type: :request do
  before do
    RubySage.reset_configuration!
    RubySage.configure { |config| config.scope = :public_rate_limited }
  end

  after { RubySage.reset_configuration! }

  it "renders the widget root on the dummy app index page" do
    get "/"

    expect(response.body).to include('id="ruby-sage-root"')
  end
end
