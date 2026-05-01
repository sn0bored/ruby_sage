# frozen_string_literal: true

class CreateRubySageScans < ActiveRecord::Migration[7.0]
  def change
    create_table :ruby_sage_scans do |t|
      t.string :status, null: false, default: "pending"
      t.string :git_sha
      t.string :ruby_version
      t.string :rails_version
      t.integer :file_count, default: 0
      t.text :errors_log
      t.datetime :started_at
      t.datetime :finished_at
      t.timestamps
    end
    add_index :ruby_sage_scans, :status
    add_index :ruby_sage_scans, :finished_at
  end
end
