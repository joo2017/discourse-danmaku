# frozen_string_literal: true

module DiscourseDanmaku
  class Like < ActiveRecord::Base
    belongs_to :item, class_name: "DiscourseDanmaku::Item"
    belongs_to :user

    validates :item, presence: true
    validates :user, presence: true
    validates :user_id, uniqueness: { scope: :item_id }
  end
end
