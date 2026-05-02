# frozen_string_literal: true

require "ruby_sage/tools/base"
require "ruby_sage/tools/database_query"
require "ruby_sage/tools/describe_table"
require "ruby_sage/tools/registry"

module RubySage
  # LLM tool definitions used by the +:admin+ mode chat loop. Each tool
  # implements +Tools::Base+ and is registered with +Tools::Registry+. The
  # registry knows how to enumerate active tools for a request and how to
  # dispatch a +tool_use+ block from the provider back to the right tool's
  # +call+ method.
  module Tools
  end
end
