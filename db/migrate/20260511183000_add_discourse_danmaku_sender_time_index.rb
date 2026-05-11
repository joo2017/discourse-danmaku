# frozen_string_literal: true

class AddDiscourseDanmakuSenderTimeIndex < ActiveRecord::Migration[7.0]
  def change
    add_index :discourse_danmaku_items,
              %i[user_id created_at],
              name: "idx_discourse_danmaku_items_on_user_id_created_at",
              if_not_exists: true
  end
end
