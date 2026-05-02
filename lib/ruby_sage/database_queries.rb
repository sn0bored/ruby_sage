# frozen_string_literal: true

require "ruby_sage/database_queries/safe_executor"

module RubySage
  # Read-only database access for the +:admin+ mode "magic search" feature.
  # Lives behind +config.enable_database_queries+ and is gated by mode +:admin+
  # in the chat controller. Three defense layers:
  #
  # 1. SQL validation — SELECT-only, single-statement.
  # 2. Mandatory rollback — every query runs inside a transaction that always
  #    raises +ActiveRecord::Rollback+, so any write that slipped past
  #    validation cannot persist.
  # 3. Statement timeout (PostgreSQL only) — bounded execution time.
  #
  # The strongest defense is configuring a read-only database user via
  # +config.query_connection+. The above layers protect against most accidents
  # but a dedicated read-only role removes the trust dependency entirely.
  module DatabaseQueries
  end
end
