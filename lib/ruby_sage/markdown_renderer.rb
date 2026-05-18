# frozen_string_literal: true

module RubySage
  # Renders markdown to HTML for knowledge-chunk bodies. Optional dependency:
  # uses +kramdown+ when it's loadable in the host app, otherwise falls back
  # to +ActionView::Helpers::TextHelper#simple_format+. Hosts can override
  # entirely via +RubySage.configuration.markdown_renderer+.
  module MarkdownRenderer
    module_function

    # @param markdown [String]
    # @return [String] HTML
    def render(markdown)
      override = RubySage.configuration.markdown_renderer
      return override.call(markdown.to_s).to_s if override.respond_to?(:call)

      kramdown(markdown.to_s) || simple_format_fallback(markdown.to_s)
    end

    def kramdown(markdown)
      require "kramdown"
      options = { auto_ids: false, hard_wrap: false }
      # GFM input adds fenced code blocks, task lists, and autolinks. It ships
      # as a separate gem (kramdown-parser-gfm); use it when available, fall
      # back to default kramdown dialect otherwise.
      begin
        require "kramdown/parser/gfm"
        options[:input] = "GFM"
      rescue LoadError
        # Default markdown dialect — still handles headers, lists, bold, links.
      end
      ::Kramdown::Document.new(markdown, options).to_html
    rescue LoadError
      nil
    end

    def simple_format_fallback(markdown)
      escaped = ERB::Util.html_escape(markdown)
      if defined?(ActionController::Base)
        ActionController::Base.helpers.simple_format(escaped)
      else
        "<pre>#{escaped}</pre>"
      end
    end
  end
end
