# frozen_string_literal: true

class CreateRubySageArtifacts < ActiveRecord::Migration[7.0]
  def change
    create_table :ruby_sage_artifacts do |t|
      t.references :scan, null: false, foreign_key: { to_table: :ruby_sage_scans }
      t.string :path, null: false
      t.string :kind
      t.string :digest, null: false
      t.text :summary
      t.text :public_symbols
      t.text :route_mappings
      t.timestamps
    end
    add_index :ruby_sage_artifacts, %i[scan_id path], unique: true
    add_index :ruby_sage_artifacts, :digest
    add_index :ruby_sage_artifacts, :kind
  end
end
