# frozen_string_literal: true

module RubySage
  # Runs a single chat query against the knowledge base and prints the result
  # to STDOUT. Used by the +ruby_sage:ask+ rake task so shell-based tools and
  # AI coding agents can query the index without opening a browser.
  #
  # @example From a rake task or shell script
  #   RubySage::CliChat.new.run("how does billing work?")
  class CliChat
    # @param config [RubySage::Configuration]
    def initialize(config: RubySage.configuration)
      @config = config
    end

    # Runs the query and prints the answer with citations.
    #
    # @param query [String] natural-language question.
    # @param show_citations [Boolean] whether to print source citations.
    # @return [void]
    def run(query, show_citations: true)
      retrieval = Retriever.new.call(query: query)

      if retrieval[:artifacts].empty?
        Rails.logger.debug "No indexed artifacts found. Run `bundle exec rake ruby_sage:scan` first."
        return
      end

      provider_response = RubySage.provider.chat(
        system_prompt: chat_system_prompt,
        cached_context: build_context(retrieval[:artifacts]),
        messages: [{ role: "user", content: query }]
      )

      Rails.logger.debug provider_response[:answer]

      if show_citations && retrieval[:citations].any?
        Rails.logger.debug "\nSources:"
        retrieval[:citations].each do |citation|
          snippet = citation[:snippet].to_s.strip
          Rails.logger.debug { "  #{citation[:path]}#{" — #{snippet}" unless snippet.empty?}" }
        end
      end
    rescue Providers::ProviderError => e
      abort "Provider error: #{e.message}"
    end

    private

    def chat_system_prompt
      RubySage::Prompts.for_mode(@config.mode)
    end

    def build_context(artifacts)
      return "" if artifacts.empty?

      blocks = artifacts.map do |artifact|
        "## #{artifact.path} (#{artifact.kind})\n\n" \
          "Public symbols: #{Array(artifact.public_symbols).join(', ')}\n\n" \
          "Summary:\n#{artifact.summary || '(no summary available)'}\n"
      end

      "Codebase context:\n\n#{blocks.join("\n---\n\n")}"
    end
  end
end
