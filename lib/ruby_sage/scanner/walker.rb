# frozen_string_literal: true

require "find"
require "pathname"

module RubySage
  class Scanner
    # Expands scanner include paths and applies exclude rules.
    class Walker
      FNM_FLAGS = File::FNM_PATHNAME | File::FNM_DOTMATCH

      # Initializes a filesystem walker for the host app.
      #
      # @param host_root [String, Pathname]
      # @param config [RubySage::Configuration]
      # @return [RubySage::Scanner::Walker]
      def initialize(host_root:, config:)
        @host_root = Pathname(host_root).expand_path
        @config = config
      end

      # Returns included file paths after config, credential, and gitignore skips.
      #
      # @return [Array<Pathname>]
      def paths
        included_files.uniq.sort.reject { |path| skip?(path) }
      end

      private

      attr_reader :host_root, :config

      def included_files
        Array(config.scanner_include).flat_map do |pattern|
          expanded_files(pattern)
        end
      end

      def expanded_files(pattern)
        matches = if glob_pattern?(pattern)
                    Dir.glob(host_root.join(pattern).to_s, FNM_FLAGS)
                  else
                    [host_root.join(pattern).to_s]
                  end
        matches.flat_map { |match| file_paths_for(Pathname(match)) }
      end

      def file_paths_for(path)
        return [] unless path.exist?
        return [path] if path.file?
        return [] unless path.directory?

        files = []
        Find.find(path) do |candidate|
          candidate_path = Pathname(candidate)
          files << candidate_path if candidate_path.file?
        end
        files
      end

      def skip?(path)
        relative = relative_path(path)
        credentials_file?(relative) || excluded_by_config?(relative) || excluded_by_gitignore?(relative)
      end

      def credentials_file?(relative)
        relative.match?(%r{\Aconfig/credentials.*\.yml\.enc\z})
      end

      def excluded_by_config?(relative)
        Array(config.scanner_exclude).any? { |pattern| path_matches?(relative, pattern) }
      end

      def excluded_by_gitignore?(relative)
        gitignore_patterns.any? { |pattern| path_matches?(relative, pattern) }
      end

      def path_matches?(relative, pattern)
        normalized = pattern.to_s.delete_prefix("/")
        return relative.start_with?(normalized) if normalized.end_with?("/")

        File.fnmatch?(normalized, relative, FNM_FLAGS) ||
          File.fnmatch?(normalized, File.basename(relative), FNM_FLAGS) ||
          relative == normalized
      end

      def gitignore_patterns
        @gitignore_patterns ||= begin
          gitignore = host_root.join(".gitignore")
          gitignore.file? ? normalized_gitignore_lines(gitignore) : []
        end
      end

      def normalized_gitignore_lines(gitignore)
        gitignore.readlines(chomp: true).filter_map do |line|
          normalize_gitignore_line(line)
        end
      end

      def normalize_gitignore_line(line)
        stripped = line.strip
        return if stripped.empty? || stripped.start_with?("#", "!")

        stripped.delete_prefix("/")
      end

      def glob_pattern?(pattern)
        pattern.to_s.match?(/[*?\[]/)
      end

      def relative_path(path)
        path.expand_path.relative_path_from(host_root).to_s
      end
    end
  end
end
