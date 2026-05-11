# frozen_string_literal: true

module DiscourseDanmaku
  module GlobalStreamEligibility
    module_function

    def eligible_for_index?(item)
      return false if item.blank? || item.status != "visible"

      eligible_for_broadcast?(item)
    end

    def eligible_for_broadcast?(item, allow_unavailable: false)
      topic, source_post = source_context(item)
      return false if topic.blank? || source_post.blank?
      return false if Permissions.category_excluded?(topic)

      Permissions.globally_visible_source?(topic: topic, post: source_post, allow_unavailable: allow_unavailable)
    end

    def eligible_for_invalidation?(item)
      eligible_for_broadcast?(item, allow_unavailable: true)
    end

    def safe_payload(type, item)
      {
        type: type.to_s,
        topic_id: item.topic_id,
        post_id: item.source_post_id,
        danmaku_id: item.id
      }
    end

    def source_context(item)
      return [nil, nil] if item.blank?

      source_post = item.source_post
      [item.topic || source_post&.topic, source_post]
    end
  end
end
