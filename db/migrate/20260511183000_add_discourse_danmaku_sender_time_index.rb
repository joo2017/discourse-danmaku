# frozen_string_literal: true

class AddDiscourseDanmakuSenderTimeIndex < ActiveRecord::Migration[7.0]
  disable_ddl_transaction!

  def change
    add_index :discourse_danmaku_items,
              %i[user_id created_at],
              name: "idx_discourse_danmaku_items_on_user_id_created_at",
              algorithm: :concurrently
  end
end
