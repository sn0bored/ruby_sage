# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubySage::Tools::Registry do
  before { RubySage.reset_configuration! }
  after { RubySage.reset_configuration! }

  describe ".for" do
    it "is empty for non-admin modes regardless of the flag" do
      RubySage.configure { |config| config.enable_database_queries = true }

      expect(described_class.for(mode: :developer)).to be_empty
      expect(described_class.for(mode: :user)).to be_empty
    end

    it "is empty in admin mode when the flag is off" do
      RubySage.configure { |config| config.enable_database_queries = false }

      expect(described_class.for(mode: :admin)).to be_empty
    end

    it "registers DatabaseQuery + DescribeTable in admin mode with the flag on" do
      RubySage.configure { |config| config.enable_database_queries = true }

      registry = described_class.for(mode: :admin)
      tool_names = registry.to_anthropic.pluck("name")

      expect(tool_names).to contain_exactly("query_database", "describe_table")
    end

    it "passes config.query_connection (when callable) to the underlying tools" do
      readonly = instance_double(
        ActiveRecord::ConnectionAdapters::AbstractAdapter,
        adapter_name: "PostgreSQL",
        table_exists?: false
      )
      RubySage.configure do |config|
        config.enable_database_queries = true
        config.query_connection = ->(_controller) { readonly }
      end

      registry = described_class.for(mode: :admin, controller: nil)
      describe_tool = registry.dispatch(name: "describe_table", input: { "table_name" => "anything" })

      expect(readonly).to have_received(:table_exists?).with("anything")
      expect(describe_tool[:error]).to eq("tool_input_error")
    end
  end

  describe "#dispatch" do
    let(:fake_tool) do
      Class.new(RubySage::Tools::Base) do
        def self.name
          "echo"
        end

        def self.description
          "Echoes its input."
        end

        def self.input_schema
          { "type" => "object" }
        end

        def call(input:)
          { received: input }
        end
      end
    end

    it "routes a tool_use call to the matching tool's #call" do
      registry = described_class.new(tools: [fake_tool.new])

      result = registry.dispatch(name: "echo", input: { "x" => 1 })

      expect(result).to eq(received: { "x" => 1 })
    end

    it "returns a tool_not_found error for an unregistered tool name" do
      registry = described_class.new(tools: [fake_tool.new])

      result = registry.dispatch(name: "missing", input: {})

      expect(result[:error]).to eq("tool_not_found")
    end
  end
end
