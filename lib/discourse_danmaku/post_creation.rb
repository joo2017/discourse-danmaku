# frozen_string_literal: true

module DiscourseDanmaku
  module PostCreation
    module_function

    def call(post:, opts:, user:)
      return result(:plugin_disabled) unless Permissions.enabled?
      return result(:not_opted_in) unless opted_in?(opts)
      return result(:missing_post) if post.blank?

      acting_user = user || post.user
      guardian = Guardian.new(acting_user)

      unless Permissions.can_send?(user: acting_user, guardian: guardian, source_post: post)
        return log_and_result(:permission_denied, post: post, user: acting_user, opts: opts)
      end

      premium_tools = Permissions.can_use_premium_tools?(user: acting_user)

      mode = premium_tools ? sanitize_mode(option_value(opts, :danmaku_mode)) : Item::MODES.first
      return log_and_result(:invalid_mode, post: post, user: acting_user, opts: opts) if mode.blank?

      color = premium_tools ? sanitize_color(option_value(opts, :danmaku_color)) : nil
      return log_and_result(:invalid_color, post: post, user: acting_user, opts: opts) if color == :invalid

      target_post = resolve_target_post(post: post, target_post_id: option_value(opts, :danmaku_target_post_id), guardian: guardian)

      existing_item = Item.find_by(source_post_id: post.id)
      return result(:already_exists, item: existing_item) if existing_item.present?

      body = post.raw.to_s
      return log_and_result(:body_too_long, post: post, user: acting_user, opts: opts) unless Permissions.within_text_limit?(body: body)

      item = Item.create!(
        topic: post.topic,
        target_post: target_post,
        source_post: post,
        user: post.user,
        body: body,
        mode: mode,
        color: color
      )

      Publisher.publish_create(item)

      result(:created, item: item)
    rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid => error
      if duplicate_source_post_error?(error)
        result(:already_exists, item: Item.find_by(source_post_id: post&.id))
      else
        log_and_result(:create_failed, post: post, user: acting_user, opts: opts, error: error)
      end
    rescue StandardError => error
      log_and_result(:unexpected_error, post: post, user: acting_user, opts: opts, error: error)
    end

    def validate_before_post_create(post:, opts:, user:)
      return unless Permissions.enabled?
      return unless opted_in?(opts)
      return if post.blank?

      acting_user = user || post.user
      error_key = preflight_error_key(post: post, user: acting_user)
      return if error_key.blank?

      post.errors.add(:base, I18n.t("danmaku.errors.#{error_key}"))
    end

    def preflight_error_key(post:, user:)
      return :login_required if user.blank?
      return :category_excluded if Permissions.category_excluded?(post.topic)
      return :premium_required unless SendingPolicy.can_send_basic_or_premium?(user: user)
      return :cooldown_active if Permissions.cooldown_active?(user: user)
      return :daily_cap_reached if Permissions.daily_cap_reached?(user: user)
      return :body_too_long unless Permissions.within_text_limit?(body: post.raw)

      nil
    end

    def opted_in?(opts)
      ActiveModel::Type::Boolean.new.cast(option_value(opts, :danmaku_enabled))
    end

    def option_value(opts, key)
      return nil if opts.blank?
      return opts[key] if opts.respond_to?(:key?) && opts.key?(key)
      return opts[key.to_s] if opts.respond_to?(:key?) && opts.key?(key.to_s)

      nil
    end

    def sanitize_mode(mode)
      normalized_mode = mode.to_s.strip
      return "scroll" if normalized_mode.blank?
      return normalized_mode if Item::MODES.include?(normalized_mode)

      nil
    end

    def sanitize_color(color)
      normalized_color = color.to_s.strip
      return nil if normalized_color.blank?
      return normalized_color if normalized_color.match?(Item::HEX_COLOR_REGEX)

      :invalid
    end

    def resolve_target_post(post:, target_post_id:, guardian:)
      target_id = target_post_id.to_i
      return nil if target_id <= 0

      target_post = Post.find_by(id: target_id)
      return nil if target_post.blank?
      return nil if target_post.topic_id != post.topic_id
      return nil unless Permissions.can_view_source?(guardian: guardian, topic: target_post.topic, post: target_post)

      target_post
    end

    def duplicate_source_post_error?(error)
      return true if error.is_a?(ActiveRecord::RecordNotUnique)
      return false unless error.is_a?(ActiveRecord::RecordInvalid)

      error.record&.errors&.added?(:source_post_id, :taken)
    end

    def log_and_result(status, post:, user:, opts:, error: nil)
      log_payload = {
        plugin: DiscourseDanmaku::PLUGIN_NAME,
        status: status,
        post_id: post&.id,
        topic_id: post&.topic_id,
        user_id: user&.id,
        source_post_user_id: post&.user_id,
        danmaku_target_post_id: option_value(opts, :danmaku_target_post_id),
        danmaku_mode: option_value(opts, :danmaku_mode)
      }

      log_payload[:error_class] = error.class.name if error
      log_payload[:error_message] = error.message if error

      Rails.logger.warn("[#{DiscourseDanmaku::PLUGIN_NAME}] post_create_danmaku=#{log_payload}")
      result(status)
    end

    def result(status, item: nil)
      { status: status, item: item }
    end
  end
end
