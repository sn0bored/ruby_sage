# frozen_string_literal: true

module RubySage
  # Generates a natural-language summary for a scanned artifact.
  class Summarizer
    SUMMARY_SYSTEM_PROMPT = <<~PROMPT
      You are summarizing a single file from a Ruby on Rails application.
      Produce a 1-2 paragraph summary that explains what the file does and how
      it relates to the rest of the app. Be specific. Mention public class/module
      names and key public methods. No fluff, no preamble.
    PROMPT

    # Initializes a summarizer using the current RubySage configuration.
    #
    # @param config [RubySage::Configuration]
    # @return [RubySage::Summarizer]
    def initialize(config: RubySage.configuration)
      @config = config
    end

    # Summarizes redacted file contents through the configured provider.
    #
    # @param contents [String] file contents after secret redaction.
    # @param path [String] relative path used as prompt context.
    # @return [String, nil] provider summary, or nil when unavailable.
    def summarize(contents:, path:)
      return nil if @config.api_key.nil?

      response = RubySage.provider.chat(
        system_prompt: SUMMARY_SYSTEM_PROMPT,
        cached_context: nil,
        messages: [{ role: "user", content: build_user_prompt(contents, path) }]
      )
      response[:answer]
    rescue NotImplementedError, StandardError => e
      Rails.logger.warn("[RubySage::Summarizer] failed to summarize #{path}: #{e.message}")
      nil
    end

    private

    def build_user_prompt(contents, path)
      "File: #{path}\n\n```ruby\n#{contents}\n```\n\nSummarize."
    end
  end
end
