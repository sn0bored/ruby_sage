# frozen_string_literal: true

class AddSignatureToRubySageArtifacts < ActiveRecord::Migration[5.2]
  def change
    add_column :ruby_sage_artifacts, :signature, :text
  end
end
