# frozen_string_literal: true

module DiscourseDanmaku
  module Lifecycle
    module_function

    def handle_source_post_change!(post, publisher: Publisher)
      return [] if post.blank?

      affected_items = Item.visible.for_source_post(post).includes(:topic, :source_post).to_a
      return [] if affected_items.empty?

      if Permissions.source_unavailable?(post) || !Permissions.within_text_limit?(body: post.raw)
        Permissions.hide_for_source_post!(post)

        affected_items.each do |item|
          publisher.publish_hide(item.reload, allow_unavailable: true)
        end

        return affected_items
      end

      affected_items.each do |item|
        item.update!(topic: post.topic, body: post.raw.to_s)
        publisher.publish_create(item)
      end

      affected_items
    end
  end
end
