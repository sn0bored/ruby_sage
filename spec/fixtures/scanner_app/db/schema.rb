# frozen_string_literal: true

ActiveRecord::Schema.define(version: 20_260_501_000_000) do
  create_table "posts", force: :cascade do |t|
    t.string "title"
  end
end
