# frozen_string_literal: true

module DiscourseDanmaku
  module ItemLikeSynchronizer
    module_function

    def like!(item:, user:, guardian:)
      return item unless mutate_like_once!(item: item, user: user)

      sync_source_post_like(item: item, user: user, guardian: guardian)
      item.reload.tap { |reloaded_item| DiscourseDanmaku::Publisher.publish_like(reloaded_item) }
    end

    def unlike!(item:, user:, guardian:)
      return item unless mutate_unlike_once!(item: item, user: user)

      sync_source_post_unlike(item: item, user: user, guardian: guardian)
      item.reload.tap { |reloaded_item| DiscourseDanmaku::Publisher.publish_like(reloaded_item) }
    end

    def mutate_like_once!(item:, user:)
      created = false

      DiscourseDanmaku::Like.transaction do
        like =
          begin
            DiscourseDanmaku::Like.find_or_create_by!(item: item, user: user)
          rescue ActiveRecord::RecordNotUnique
            DiscourseDanmaku::Like.find_by(item: item, user: user)
          end

        if like&.previously_new_record?
          DiscourseDanmaku::Item.where(id: item.id).update_all("likes_count = COALESCE(likes_count, 0) + 1")
          created = true
        end
      end

      created
    end

    def mutate_unlike_once!(item:, user:)
      destroyed = false

      DiscourseDanmaku::Like.transaction do
        like = DiscourseDanmaku::Like.find_by(item: item, user: user)

        if like
          like.destroy!
          DiscourseDanmaku::Item.where(id: item.id).update_all("likes_count = GREATEST(COALESCE(likes_count, 0) - 1, 0)")
          destroyed = true
        end
      end

      destroyed
    end

    def sync_source_post_like(item:, user:, guardian:)
      source_post = item.source_post
      return if source_post.blank?
      return if source_post.user_id == user.id
      return unless guardian.can_see?(source_post)
      return if source_post_liked?(source_post: source_post, user: user)

      PostActionCreator.like(user, source_post)
    rescue ActiveRecord::RecordInvalid, Discourse::InvalidAccess
      nil
    end

    def sync_source_post_unlike(item:, user:, guardian:)
      source_post = item.source_post
      return if source_post.blank?
      return if source_post.user_id == user.id
      return unless guardian.can_see?(source_post)
      return unless source_post_liked?(source_post: source_post, user: user)

      PostActionDestroyer.destroy(user, source_post, :like, skip_delete_check: true)
    rescue ActiveRecord::RecordInvalid, Discourse::InvalidAccess
      nil
    end

    def source_post_liked?(source_post:, user:)
      PostAction.exists?(
        user_id: user.id,
        post_id: source_post.id,
        post_action_type_id: PostActionType.types[:like]
      )
    end
  end
end
