# frozen_string_literal: true

module DiscourseDanmaku
  class ItemSerializer < ApplicationSerializer
    attributes :id,
               :topic_id,
               :target_post_id,
               :source_post_id,
               :user_id,
               :username,
               :body,
               :mode,
               :color,
               :likes_count,
               :liked_by_current_user,
               :can_like_by_current_user,
               :replies_count,
               :status,
               :created_at,
               :source_topic_title,
               :source_topic_url,
               :source_post_url

    def username
      object.user&.username
    end

    def body
      return nil unless can_view_body?

      object.body
    end

    def source_topic_title
      return nil unless can_view_body?

      object.topic&.title
    end

    def source_topic_url
      return nil unless can_view_body?

      topic = object.topic
      return topic.url if topic&.respond_to?(:url)
      return topic.relative_url if topic&.respond_to?(:relative_url)

      nil
    end

    def source_post_url
      return nil unless can_view_body?

      post = object.source_post
      return post.url if post&.respond_to?(:url)

      nil
    end

    def liked_by_current_user
      user = serializer_guardian.user
      return false if user.blank?

      liked_item_ids = serializer_liked_item_ids
      return liked_item_ids.include?(object.id) unless liked_item_ids.nil?

      object.likes.exists?(user_id: user.id)
    end

    def can_like_by_current_user
      DiscourseDanmaku::Permissions.can_like?(user: serializer_guardian.user, guardian: serializer_guardian, item: object)
    end

    private

    def can_view_body?
      return @can_view_body if defined?(@can_view_body)

      @can_view_body = object.status == "visible" && DiscourseDanmaku::Permissions.can_view_item?(guardian: serializer_guardian, item: object)
    end

    def serializer_guardian
      return scope if scope.is_a?(Guardian)
      return scope[:guardian] if scope.is_a?(Hash) && scope[:guardian].is_a?(Guardian)

      Guardian.new(scope.respond_to?(:user) ? scope.user : nil)
    end

    def serializer_liked_item_ids
      return nil unless scope.is_a?(Hash) && scope.key?(:liked_item_ids)

      scope[:liked_item_ids]
    end
  end
end
