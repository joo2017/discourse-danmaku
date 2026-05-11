# frozen_string_literal: true

module DiscourseDanmaku
  module SendingPolicy
    module_function

    def can_send?(user:, guardian:, source_post:)
      return false unless Permissions.enabled?
      return false if user.blank? || guardian.blank? || source_post.blank?
      return false if Permissions.category_excluded?(source_post.topic)
      return false unless Permissions.can_view_source?(guardian: guardian, topic: source_post.topic, post: source_post)
      return false unless guardian.can_create_post_on_topic?(source_post.topic)
      return false if sending_restricted?(user)
      return false unless can_send_basic_or_premium?(user: user)
      return false if cooldown_active?(user: user)
      return false if daily_cap_reached?(user: user)

      true
    end

    def can_send_basic_or_premium?(user:)
      return false unless Permissions.enabled?
      return false if user.blank?
      return true if can_use_premium_tools?(user: user)

      SiteSetting.danmaku_allow_basic_users
    end

    def can_use_premium_tools?(user:)
      return false unless Permissions.enabled?
      return false if user.blank?
      return true if staff_bypass? && user.staff?

      group_ids = premium_group_ids
      group_ids.present? && user.in_any_groups?(group_ids)
    end

    def cooldown_active?(user:)
      return false if user.blank?

      seconds = SiteSetting.danmaku_send_rate_limit_seconds.to_i
      return false if seconds <= 0

      last_created_at = Item.where(user_id: user.id).maximum(:created_at)
      return false if last_created_at.blank?

      last_created_at > seconds.seconds.ago
    end

    def daily_cap_reached?(user:, now: Time.zone.now)
      return false if user.blank?

      limit = SiteSetting.danmaku_daily_limit_per_user.to_i
      return false if limit <= 0

      Item.where(user_id: user.id, created_at: now.beginning_of_day..now).count >= limit
    end

    def within_text_limit?(body:)
      body.to_s.length <= SiteSetting.danmaku_max_text_length.to_i
    end

    def premium_group_ids
      mapped_ids = Array(SiteSetting.danmaku_premium_group_names_map.presence || [])
        .filter_map { |group_id| group_id.to_i if group_id.to_i.positive? }

      raw_values =
        case (raw_setting = SiteSetting.danmaku_premium_group_names)
        when String
          raw_setting.split(/[|,]/)
        when Array
          raw_setting
        else
          Array(raw_setting)
        end

      names = raw_values.map(&:to_s).map(&:strip).reject(&:blank?).reject { |value| value.match?(/\A\d+\z/) }
      explicit_ids = raw_values.filter_map { |value| value.to_i if value.to_s.match?(/\A\d+\z/) && value.to_i.positive? }
      named_ids = names.present? ? Group.where(name: names).pluck(:id) : []

      (mapped_ids + explicit_ids + named_ids).uniq
    end

    def staff_bypass?
      SiteSetting.danmaku_staff_bypass
    end

    def sending_restricted?(user)
      return true if truthy_user_state?(user, :suspended?)
      return true if truthy_user_state?(user, :silenced?)
      return true if user.respond_to?(:suspended_till) && user.suspended_till.present? && user.suspended_till > Time.zone.now

      user.respond_to?(:silenced_till) && user.silenced_till.present? && user.silenced_till > Time.zone.now
    end

    def truthy_user_state?(user, method_name)
      user.respond_to?(method_name) && user.public_send(method_name)
    end
  end
end
