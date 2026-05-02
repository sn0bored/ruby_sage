# frozen_string_literal: true

class AddAudiencesToRubySageArtifacts < ActiveRecord::Migration[5.2]
  def change
    add_column :ruby_sage_artifacts, :audiences, :text
  end
end
