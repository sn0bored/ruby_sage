# frozen_string_literal: true

namespace :ruby_sage do
  desc "Scan the host application's codebase and produce a knowledge snapshot."
  task scan: :environment do
    scan = RubySage::Scanner.new(host_root: Rails.root).run
    puts "Scan ##{scan.id} #{scan.status} - #{scan.file_count} files, " \
         "#{scan.artifacts.count} artifacts."
  end
end
