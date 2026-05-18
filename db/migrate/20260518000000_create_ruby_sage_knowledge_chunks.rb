# frozen_string_literal: true

class CreateRubySageKnowledgeChunks < ActiveRecord::Migration[5.2]
  def change
    create_table :ruby_sage_knowledge_chunks do |t|
      t.string  :slug,      null: false
      t.string  :title,     null: false
      t.text    :body,      null: false
      t.text    :tags
      t.text    :audiences
      t.integer :position
      t.boolean :published, null: false, default: true
      t.string  :url
      t.string  :video_url
      t.string  :source, null: false, default: "admin_ui"
      t.text    :metadata
      t.timestamps
    end

    add_index :ruby_sage_knowledge_chunks, :slug, unique: true
    add_index :ruby_sage_knowledge_chunks, :position
    add_index :ruby_sage_knowledge_chunks, :source
    add_index :ruby_sage_knowledge_chunks, :published
  end
end
