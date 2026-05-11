# frozen_string_literal: true

# name: discourse-danmaku
# about: Danmaku overlays for Discourse
# version: 0.0.1
# authors: Discourse
# required_version: 2.7.0

enabled_site_setting :danmaku_enabled

register_asset "stylesheets/common/danmaku.scss"

module ::DiscourseDanmaku
  PLUGIN_NAME = "discourse-danmaku"

  module LabelFormatterExtension
    def humanized_name(setting)
      translated_name = I18n.t("site_settings.humanized_names.#{setting}", default: nil)
      return translated_name if translated_name.present?

      super
    end
  end
end

require_relative "lib/discourse_danmaku/engine"

after_initialize do
  require_relative "lib/discourse_danmaku/permissions"
  require_relative "lib/discourse_danmaku/sending_policy"
  require_relative "lib/discourse_danmaku/global_stream_eligibility"
  require_relative "lib/discourse_danmaku/guardian_extension"
  require_relative "lib/discourse_danmaku/post_creation"
  require_relative "lib/discourse_danmaku/post_creator_extension"
  require_relative "lib/discourse_danmaku/publisher"
  require_relative "lib/discourse_danmaku/lifecycle"
  require_relative "lib/discourse_danmaku/item_query"
  require_relative "lib/discourse_danmaku/item_like_synchronizer"

  add_permitted_post_create_param(:danmaku_enabled)
  add_permitted_post_create_param(:danmaku_target_post_id)
  add_permitted_post_create_param(:danmaku_mode)
  add_permitted_post_create_param(:danmaku_color)

  add_to_serializer(:current_user, :can_use_danmaku_premium_tools) do
    scope.can_use_danmaku_premium_tools?
  end

  on(:before_create_post) do |post, opts|
    DiscourseDanmaku::PostCreatorExtension.validate_before_post_create(post: post, opts: opts, user: post&.user)
  end

  on(:post_created) do |post, opts, user|
    DiscourseDanmaku::PostCreatorExtension.call(post: post, opts: opts, user: user)
  end

  on(:post_edited) do |post, *_args|
    DiscourseDanmaku::Lifecycle.handle_source_post_change!(post)
  end

  on(:post_destroyed) do |post, *_args|
    DiscourseDanmaku::Lifecycle.handle_source_post_change!(post)
  end

  SiteSettings::LabelFormatter.singleton_class.prepend(DiscourseDanmaku::LabelFormatterExtension) unless SiteSettings::LabelFormatter.singleton_class.ancestors.include?(DiscourseDanmaku::LabelFormatterExtension)

  Guardian.prepend(DiscourseDanmaku::GuardianExtension) unless Guardian.ancestors.include?(DiscourseDanmaku::GuardianExtension)
end
