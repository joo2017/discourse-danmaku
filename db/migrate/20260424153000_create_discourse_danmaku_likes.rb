# frozen_string_literal: true

class CreateDiscourseDanmakuLikes < ActiveRecord::Migration[7.0]
  def change
    create_table :discourse_danmaku_likes do |t|
      t.bigint :item_id, null: false
      t.bigint :user_id, null: false

      t.timestamps
    end

    add_index :discourse_danmaku_likes, [:item_id, :user_id], unique: true
    add_index :discourse_danmaku_likes, :user_id
  end
end
