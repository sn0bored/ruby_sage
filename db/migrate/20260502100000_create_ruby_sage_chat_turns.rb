# frozen_string_literal: true

class CreateRubySageChatTurns < ActiveRecord::Migration[5.2]
  def change
    create_table :ruby_sage_chat_turns do |t|
      t.references :scan, foreign_key: { to_table: :ruby_sage_scans, on_delete: :nullify }
      t.string :mode, null: false
      t.text :question, null: false
      t.text :answer
      t.text :tool_calls
      t.text :citations
      t.integer :input_tokens
      t.integer :output_tokens
      t.integer :cache_creation_tokens
      t.integer :cache_read_tokens
      t.integer :iterations
      t.string :status, null: false, default: "completed"
      t.text :error_message
      t.references :asker, polymorphic: true
      t.string :session_id
      t.timestamps
    end
    add_index :ruby_sage_chat_turns, :status
    add_index :ruby_sage_chat_turns, :mode
    add_index :ruby_sage_chat_turns, :session_id
    add_index :ruby_sage_chat_turns, :created_at
  end
end
