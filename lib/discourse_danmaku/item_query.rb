# frozen_string_literal: true

module DiscourseDanmaku
  module ItemQuery
    module_function

    def base_scope
      DiscourseDanmaku::Item.visible.includes(:topic, :user, :source_post)
    end

    def list(base_scope:, after_id:, limit:, visibility_check:)
      limit = limit.to_i
      return [] if base_scope.blank? || limit <= 0 || visibility_check.blank?

      return latest(base_scope: base_scope, limit: limit, visibility_check: visibility_check) if after_id.to_i <= 0

      visible_items = []
      last_seen_id = [after_id.to_i, 0].max
      batch_limit = limit

      loop do
        candidates =
          base_scope
            .where("discourse_danmaku_items.id > ?", last_seen_id)
            .order(id: :asc)
            .limit(batch_limit)
            .to_a
        break if candidates.empty?

        candidates.each do |item|
          visible_items << item if visibility_check.call(item)
          break if visible_items.length >= limit
        end

        break if visible_items.length >= limit || candidates.length < batch_limit

        last_seen_id = candidates.last.id
      end

      visible_items
    end

    def latest(base_scope:, limit:, visibility_check:)
      visible_items = []
      before_id = nil
      batch_limit = limit

      loop do
        candidates = base_scope.order(id: :desc)
        candidates = candidates.where("discourse_danmaku_items.id < ?", before_id) if before_id
        candidates = candidates.limit(batch_limit).to_a
        break if candidates.empty?

        candidates.each do |item|
          visible_items << item if visibility_check.call(item)
          break if visible_items.length >= limit
        end

        break if visible_items.length >= limit || candidates.length < batch_limit

        before_id = candidates.last.id
      end

      visible_items.reverse
    end

    def globally_visible?(item)
      DiscourseDanmaku::GlobalStreamEligibility.eligible_for_index?(item)
    end
  end
end
