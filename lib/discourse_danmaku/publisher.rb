# frozen_string_literal: true

module DiscourseDanmaku
  module Publisher
    CHANNEL = "/danmaku/global".freeze
    RATE_LIMIT_CACHE_KEY_PREFIX = "discourse_danmaku_global_broadcast".freeze
    FALLBACK_RATE_LIMIT_MUTEX = Mutex.new

    module_function

    def publish_create(item, message_bus: MessageBus, cache: Discourse.cache, now: Time.zone.now)
      publish(:create, item, message_bus: message_bus, cache: cache, now: now)
    end

    def publish_like(item, message_bus: MessageBus, cache: Discourse.cache, now: Time.zone.now)
      publish(:like, item, message_bus: message_bus, cache: cache, now: now)
    end

    def publish_hide(item, message_bus: MessageBus, cache: Discourse.cache, now: Time.zone.now, allow_unavailable: false)
      publish(:hide, item, message_bus: message_bus, cache: cache, now: now, allow_unavailable: allow_unavailable)
    end

    def publish(type, item, message_bus: MessageBus, cache: Discourse.cache, now: Time.zone.now, allow_unavailable: false)
      return false unless publishable_globally?(item, allow_unavailable: allow_unavailable)
      return false unless consume_broadcast_slot?(cache: cache, now: now)

      message_bus.publish(CHANNEL, safe_payload(type, item))
      true
    rescue StandardError => error
      Rails.logger.warn(
        "[#{DiscourseDanmaku::PLUGIN_NAME}] message_bus_publish_failed=" \
          "#{ { type: type, danmaku_id: item&.id, error_class: error.class.name, error_message: error.message } }"
      )
      false
    end

    def publishable_globally?(item, allow_unavailable: false)
      GlobalStreamEligibility.eligible_for_broadcast?(item, allow_unavailable: allow_unavailable)
    end

    def safe_payload(type, item)
      GlobalStreamEligibility.safe_payload(type, item)
    end

    def consume_broadcast_slot?(cache:, now: Time.zone.now)
      limit = SiteSetting.danmaku_global_broadcast_limit_per_minute.to_i
      return true if limit <= 0

      key = broadcast_rate_limit_key(now)
      count = increment_broadcast_count(cache: cache, key: key)

      count <= limit
    end

    def increment_broadcast_count(cache:, key:)
      if cache.respond_to?(:increment)
        count = cache.increment(key, 1, expires_in: 1.minute)
        return count.to_i if count
      end

      FALLBACK_RATE_LIMIT_MUTEX.synchronize do
        count = cache.read(key).to_i
        cache.write(key, count + 1, expires_in: 1.minute)
        count + 1
      end
    end

    def broadcast_rate_limit_key(now = Time.zone.now)
      "#{RATE_LIMIT_CACHE_KEY_PREFIX}:#{now.beginning_of_minute.to_i}"
    end
  end
end
