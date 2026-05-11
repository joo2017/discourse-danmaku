# frozen_string_literal: true

module DiscourseDanmaku
  class ItemsController < ::ApplicationController
    MAX_FETCH_LIMIT = 100

    requires_plugin DiscourseDanmaku::PLUGIN_NAME

    before_action :ensure_logged_in, only: %i[like hide]

    def global
      render_json_dump(items: serialized_items(fetch_items(base_scope: base_items_scope, visibility_check: method(:globally_visible_item?))))
    end

    def index
      topic = find_topic
      raise Discourse::InvalidAccess unless topic.nil? || guardian.can_see?(topic)

      scoped_items = base_items_scope
      scoped_items = scoped_items.where(topic_id: topic.id) if topic

      render_json_dump(items: serialized_items(fetch_items(base_scope: scoped_items, visibility_check: method(:locally_visible_item?))))
    end

    def show
      item = find_visible_item!(params[:id])

      render_json_dump(item: serialized_item(item))
    end

    def like
      item = find_visible_item!(params[:id])
      raise Discourse::InvalidAccess unless DiscourseDanmaku::Permissions.can_like?(user: current_user, guardian: guardian, item: item)

      item = DiscourseDanmaku::ItemLikeSynchronizer.like!(item: item, user: current_user, guardian: guardian)

      render_json_dump(item: serialized_item(item))
    end

    def unlike
      item = find_visible_item!(params[:id])
      raise Discourse::InvalidAccess unless DiscourseDanmaku::Permissions.can_unlike?(user: current_user, guardian: guardian, item: item)

      item = DiscourseDanmaku::ItemLikeSynchronizer.unlike!(item: item, user: current_user, guardian: guardian)

      render_json_dump(item: serialized_item(item))
    end

    def hide
      item = base_items_scope.find_by(id: params[:id])
      raise Discourse::NotFound if item.blank?
      raise Discourse::InvalidAccess unless guardian.can_moderate_danmaku?

      previous_status = item.status
      item.update!(status: requested_hide_status)
      item = item.reload
      DiscourseDanmaku::Publisher.publish_hide(item) if previous_status != item.status

      render_json_dump(item: serialized_item(item))
    end

    private

    def base_items_scope
      DiscourseDanmaku::ItemQuery.base_scope
    end

    def fetch_items(base_scope:, visibility_check: method(:locally_visible_item?))
      DiscourseDanmaku::ItemQuery.list(
        base_scope: base_scope,
        after_id: parsed_after_id,
        limit: parsed_limit,
        visibility_check: visibility_check
      )
    end

    def locally_visible_item?(item)
      DiscourseDanmaku::Permissions.can_view_item?(guardian: guardian, item: item)
    end

    def globally_visible_item?(item)
      DiscourseDanmaku::ItemQuery.globally_visible?(item)
    end

    def find_topic
      return nil if params[:topic_id].blank?

      topic_id = params[:topic_id].to_i
      return nil if topic_id <= 0

      Topic.find_by(id: topic_id) || raise(Discourse::NotFound)
    end

    def find_visible_item!(item_id)
      item = base_items_scope.find_by(id: item_id)
      raise Discourse::NotFound if item.blank?
      raise Discourse::NotFound unless DiscourseDanmaku::Permissions.can_view_item?(guardian: guardian, item: item)

      item
    end

    def parsed_after_id
      value = params[:after_id].to_i
      value.positive? ? value : 0
    end

    def parsed_limit
      configured_limit = SiteSetting.danmaku_initial_fetch_limit.to_i
      configured_limit = 1 if configured_limit <= 0

      requested_limit = params[:limit].to_i
      requested_limit = configured_limit if requested_limit <= 0

      [requested_limit, configured_limit, MAX_FETCH_LIMIT].min
    end

    def requested_hide_status
      requested_status = params[:status].to_s
      return "deleted" if requested_status == "deleted"
      return "deleted" if ActiveModel::Type::Boolean.new.cast(params[:deleted])

      "hidden"
    end

    def serialized_items(items)
      liked_item_ids = current_user_liked_item_ids(items)

      items.map { |item| serialized_item(item, liked_item_ids: liked_item_ids) }
    end

    def serialized_item(item, liked_item_ids: nil)
      DiscourseDanmaku::ItemSerializer.new(item, scope: serializer_scope(liked_item_ids), root: false).as_json
    end

    def serializer_scope(liked_item_ids)
      return guardian if liked_item_ids.nil?

      { guardian: guardian, liked_item_ids: liked_item_ids }
    end

    def current_user_liked_item_ids(items)
      return [] if current_user.blank? || items.blank?

      DiscourseDanmaku::Like.where(user_id: current_user.id, item_id: items.map(&:id)).pluck(:item_id)
    end
  end
end
