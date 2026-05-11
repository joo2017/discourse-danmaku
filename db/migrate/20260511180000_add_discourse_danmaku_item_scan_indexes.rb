# frozen_string_literal: true

class AddDiscourseDanmakuItemScanIndexes < ActiveRecord::Migration[7.0]
  disable_ddl_transaction!

  def change
    add_index :discourse_danmaku_items,
              :id,
              name: "idx_discourse_danmaku_visible_items_on_id",
              where: "status = 'visible'",
              algorithm: :concurrently

    add_index :discourse_danmaku_items,
              %i[topic_id id],
              name: "idx_discourse_danmaku_visible_items_on_topic_id_id",
              where: "status = 'visible'",
              algorithm: :concurrently
  end
end
