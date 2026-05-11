# frozen_string_literal: true

class CreateDiscourseDanmakuItems < ActiveRecord::Migration[7.0]
  def change
    create_table :discourse_danmaku_items do |t|
      t.bigint :topic_id, null: false
      t.bigint :target_post_id
      t.bigint :source_post_id
      t.bigint :user_id, null: false
      t.text :body, null: false
      t.string :mode, null: false, default: "scroll"
      t.string :color
      t.integer :likes_count, null: false, default: 0
      t.integer :replies_count, null: false, default: 0
      t.string :status, null: false, default: "visible"

      t.timestamps
    end

    add_index :discourse_danmaku_items, [:topic_id, :id]
    add_index :discourse_danmaku_items, [:target_post_id, :id]
    add_index :discourse_danmaku_items, :user_id
    add_index :discourse_danmaku_items,
              :source_post_id,
              unique: true,
              where: "source_post_id IS NOT NULL"
  end
end
