# frozen_string_literal: true

module DiscourseDanmaku
  module Permissions
    @excluded_category_ids_cache_key = nil
    @excluded_category_ids_cache_value = nil

    module_function

    def can_view_item?(guardian:, item:)
      return false unless enabled?
      return false if item.blank? || item.status != "visible"

      topic = item.topic || item.source_post&.topic
      post = item.source_post

      can_view_source?(guardian: guardian, topic: topic, post: post)
    end

    def can_view_source?(guardian:, topic:, post:)
      return false unless enabled?
      return false if guardian.blank? || topic.blank? || post.blank?
      return false if category_excluded?(topic)
      return false if source_unavailable?(post)
      return false unless guardian.can_see?(topic) && guardian.can_see?(post)

      true
    end

    def globally_visible_source?(topic:, post:, allow_unavailable: false)
      return false unless enabled?
      return false if topic.blank? || post.blank?
      return false unless publicly_visible_topic?(topic: topic)
      return false if !allow_unavailable && source_unavailable?(post)
      return false if global_public_only? && !allow_unavailable && !publicly_visible_post?(post: post)

      true
    end

    def can_send?(user:, guardian:, source_post:)
      SendingPolicy.can_send?(user: user, guardian: guardian, source_post: source_post)
    end

    def can_use_premium_tools?(user:)
      SendingPolicy.can_use_premium_tools?(user: user)
    end

    def can_like?(user:, guardian:, item:)
      return false unless enabled?
      return false if user.blank?
      return false if authored_by?(item: item, user: user)

      can_view_item?(guardian: guardian, item: item)
    end

    def can_unlike?(user:, guardian:, item:)
      return false unless enabled?
      return false if user.blank?

      can_view_item?(guardian: guardian, item: item)
    end

    def can_moderate?(user:)
      user.present? && user.staff?
    end

    def cooldown_active?(user:)
      SendingPolicy.cooldown_active?(user: user)
    end

    def daily_cap_reached?(user:, now: Time.zone.now)
      SendingPolicy.daily_cap_reached?(user: user, now: now)
    end

    def within_text_limit?(body:)
      SendingPolicy.within_text_limit?(body: body)
    end

    def hide_for_source_post!(post)
      return 0 if post.blank?

      Item.for_source_post(post).where.not(status: "deleted").update_all(status: "hidden", updated_at: Time.zone.now)
    end

    def source_unavailable?(post)
      return true if truthy_post_state?(post, :hidden?)
      return true if truthy_post_state?(post, :trashed?)
      return true if truthy_post_state?(post, :deleted?)

      post.respond_to?(:deleted_at) && post.deleted_at.present?
    end

    def enabled?
      SiteSetting.danmaku_enabled
    end

    def premium_group_ids
      SendingPolicy.premium_group_ids
    end

    def staff_bypass?
      SendingPolicy.staff_bypass?
    end

    def global_public_only?
      SiteSetting.danmaku_global_public_only
    end

    def excluded_category_ids
      raw_value = SiteSetting.danmaku_excluded_category_ids
      cache_key = excluded_category_ids_cache_key(raw_value)
      return @excluded_category_ids_cache_value if @excluded_category_ids_cache_key == cache_key

      values =
        case raw_value
        when String
          raw_value.split(/[|,]/)
        when Array
          raw_value
        else
          Array(raw_value)
        end

      @excluded_category_ids_cache_key = cache_key
      @excluded_category_ids_cache_value = values.reject(&:blank?).map(&:to_i)
    end

    def excluded_category_ids_cache_key(raw_value)
      case raw_value
      when Array
        raw_value.map(&:to_s).join("\u0000")
      else
        raw_value.to_s
      end
    end

    def category_excluded?(topic)
      return false if topic.blank?

      excluded_category_ids.include?(topic.category_id.to_i)
    end

    def publicly_visible?(topic:, post:)
      publicly_visible_topic?(topic: topic) && publicly_visible_post?(post: post)
    end

    def publicly_visible_topic?(topic:)
      anonymous_guardian = Guardian.new(nil)

      anonymous_guardian.can_see?(topic)
    end

    def publicly_visible_post?(post:)
      anonymous_guardian = Guardian.new(nil)

      anonymous_guardian.can_see?(post)
    end

    def sending_restricted?(user)
      SendingPolicy.sending_restricted?(user)
    end

    def authored_by?(item:, user:)
      return false if item.blank? || user.blank?

      item.user_id == user.id || item.source_post&.user_id == user.id
    end

    def truthy_post_state?(post, method_name)
      post.respond_to?(method_name) && post.public_send(method_name)
    end

    def truthy_user_state?(user, method_name)
      SendingPolicy.truthy_user_state?(user, method_name)
    end
  end
end
