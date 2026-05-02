# frozen_string_literal: true

class AddModelToRubySageChatTurns < ActiveRecord::Migration[5.2]
  def change
    add_column :ruby_sage_chat_turns, :model, :string
    add_index :ruby_sage_chat_turns, :model
  end
end
