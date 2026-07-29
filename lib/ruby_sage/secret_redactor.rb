# frozen_string_literal: true

module RubySage
  # Strips secret values while preserving key names and ENV references.
  class SecretRedactor
    SECRET_KEY_PATTERN = /(api_key|secret|password|token|access[_-]?key|private[_-]?key|client[_-]?secret)/i
    YAML_VALUE_LINE = /\A(\s*[\w-]+):\s*(['"]?)(.*?)\2\s*\z/

    # Initializes a redactor for one file's contents.
    #
    # @param contents [String] file contents to sanitize.
    # @return [RubySage::SecretRedactor]
    def initialize(contents)
      @contents = contents
    end

    # Replaces YAML secret-looking values with a stable redaction marker.
    #
    # @return [String]
    def call
      @contents.lines.map do |line|
        redact_line(line)
      end.join
    end

    private

    def redact_line(line)
      match = line.match(YAML_VALUE_LINE)
      return line unless match&.[](1)&.match?(SECRET_KEY_PATTERN)

      "#{match[1]}: [REDACTED]\n"
    end
  end
end
