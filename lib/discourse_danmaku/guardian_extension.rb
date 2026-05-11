# frozen_string_literal: true

module DiscourseDanmaku
  module GuardianExtension
    def can_view_danmaku_item?(item)
      Permissions.can_view_item?(guardian: self, item: item)
    end

    def can_view_danmaku_source?(topic, post)
      Permissions.can_view_source?(guardian: self, topic: topic, post: post)
    end

    def can_send_danmaku?(source_post)
      Permissions.can_send?(user: user, guardian: self, source_post: source_post)
    end

    def can_use_danmaku_premium_tools?
      Permissions.can_use_premium_tools?(user: user)
    end

    def can_like_danmaku?(item)
      Permissions.can_like?(user: user, guardian: self, item: item)
    end

    def can_moderate_danmaku?
      Permissions.can_moderate?(user: user)
    end
  end
end
