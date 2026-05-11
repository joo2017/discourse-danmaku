# frozen_string_literal: true

module DiscourseDanmaku
  class Item < ActiveRecord::Base
    MODES = %w[scroll top bottom].freeze
    STATUSES = %w[visible hidden deleted].freeze
    HEX_COLOR_REGEX = /\A#(?:\h{3}|\h{6}|\h{8})\z/i

    belongs_to :topic
    belongs_to :target_post, class_name: "Post", optional: true
    belongs_to :source_post, class_name: "Post"
    belongs_to :user
    has_many :likes, class_name: "DiscourseDanmaku::Like", dependent: :destroy

    scope :visible, -> { where(status: "visible") }
    scope :for_source_post, ->(post) { where(source_post_id: post&.id) }

    validates :body, presence: true, length: { maximum: ->(_) { SiteSetting.danmaku_max_text_length } }
    validates :mode, presence: true, inclusion: { in: MODES }
    validates :color, allow_blank: true, format: { with: HEX_COLOR_REGEX }
    validates :status, presence: true, inclusion: { in: STATUSES }
    validates :likes_count, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
    validates :replies_count, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
    validates :source_post_id, uniqueness: true, allow_nil: true

    def hidden?
      status == "hidden"
    end

    def deleted?
      status == "deleted"
    end
  end
end
