# frozen_string_literal: true

module RubySage
  # Calculates USD cost for one chat turn given model + usage. Pricing is
  # quoted in dollars-per-million-tokens, the canonical unit both Anthropic
  # and OpenAI publish.
  #
  # Built-in pricing covers the gem's default models. Hosts can override or
  # extend via +config.model_pricing+:
  #
  #   config.model_pricing["my-fine-tune"] = {
  #     input_per_million: 2.5,
  #     output_per_million: 10.0,
  #     cache_read_per_million: 0.25,
  #     cache_write_per_million: 3.0
  #   }
  #
  # If the model is unknown and no override exists, +call+ returns nil — the
  # admin views render a "—" rather than guessing.
  class CostCalculator
    DEFAULT_PRICING = {
      "claude-opus-4-7" => {
        input_per_million: 15.0,
        output_per_million: 75.0,
        cache_read_per_million: 1.50,
        cache_write_per_million: 18.75
      },
      "claude-sonnet-4-6" => {
        input_per_million: 3.0,
        output_per_million: 15.0,
        cache_read_per_million: 0.30,
        cache_write_per_million: 3.75
      },
      "claude-haiku-4-5" => {
        input_per_million: 1.0,
        output_per_million: 5.0,
        cache_read_per_million: 0.10,
        cache_write_per_million: 1.25
      },
      "gpt-4.1" => {
        input_per_million: 2.0,
        output_per_million: 8.0
      },
      "gpt-4.1-mini" => {
        input_per_million: 0.40,
        output_per_million: 1.60
      }
    }.freeze

    # Returns the merged pricing map (defaults + +config.model_pricing+).
    #
    # @return [Hash{String => Hash}]
    def self.pricing(config: RubySage.configuration)
      DEFAULT_PRICING.merge(config.model_pricing || {})
    end

    # Calculates USD cost for one chat turn.
    #
    # @param model [String, nil] e.g. +"claude-sonnet-4-6"+.
    # @param input_tokens [Integer]
    # @param output_tokens [Integer]
    # @param cache_read_tokens [Integer]
    # @param cache_creation_tokens [Integer]
    # @param config [RubySage::Configuration]
    # @return [Float, nil] USD cost, or nil when the model is unknown.
    def self.call(model:, config: RubySage.configuration, **token_counts)
      return nil if model.to_s.empty?

      rates = pricing(config: config)[model.to_s]
      return nil if rates.nil?

      tokens_to_dollars(rates, token_counts)
    end

    def self.tokens_to_dollars(rates, token_counts)
      per_million = 1_000_000.0
      [
        [token_counts[:input_tokens],          rates[:input_per_million]],
        [token_counts[:output_tokens],         rates[:output_per_million]],
        [token_counts[:cache_read_tokens],     rates[:cache_read_per_million]],
        [token_counts[:cache_creation_tokens], rates[:cache_write_per_million]]
      ].sum { |tokens, rate| tokens.to_i * (rate || 0) / per_million }
    end
    private_class_method :tokens_to_dollars
  end
end
