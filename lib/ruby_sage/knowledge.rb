# frozen_string_literal: true

module RubySage
  # Top-level namespace for the curated knowledge layer.
  #
  # Knowledge chunks are how-to / FAQ entries authored by the host app's
  # team (either as YAML files at +config/ruby_sage/knowledge/*.yml+ or
  # via the admin CRUD UI). The retriever surfaces them alongside scanned
  # code artifacts; they outrank auto-summarized code in +:admin+ and
  # +:user+ modes because human-curated trumps inferred.
  module Knowledge
    autoload :Loader,       "ruby_sage/knowledge/loader"
    autoload :Syncer,       "ruby_sage/knowledge/syncer"
    autoload :AgentPlanner, "ruby_sage/knowledge/agent_planner"
    autoload :AgentApplier, "ruby_sage/knowledge/agent_applier"

    # Resolves the configured knowledge directory, falling back to the
    # host's +Rails.root/config/ruby_sage/knowledge+.
    #
    # @return [Pathname]
    def self.path
      configured = RubySage.configuration.knowledge_path
      return Pathname.new(configured.to_s) if configured

      Pathname.new(Rails.root.join("config/ruby_sage/knowledge").to_s)
    end
  end
end
