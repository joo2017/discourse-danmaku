# frozen_string_literal: true

require "rails_helper"

RSpec.describe DiscourseDanmaku::PostCreatorExtension do
  fab!(:topic)
  fab!(:user)
  fab!(:premium_group) { Fabricate(:group, name: "danmaku_premium") }
  fab!(:source_post) { Fabricate(:post, topic: topic, user: user, raw: "source snapshot") }
  fab!(:same_topic_target_post) { Fabricate(:post, topic: topic) }
  fab!(:other_topic)
  fab!(:other_topic_target_post) { Fabricate(:post, topic: other_topic) }

  let(:base_opts) do
    {
      danmaku_enabled: true,
      danmaku_mode: "scroll",
      danmaku_color: "#abc",
      danmaku_target_post_id: same_topic_target_post.id
    }
  end

  before do
    SiteSetting.stubs(:danmaku_enabled).returns(true)
    SiteSetting.stubs(:danmaku_global_public_only).returns(true)
    SiteSetting.stubs(:danmaku_excluded_category_ids).returns([])
    SiteSetting.stubs(:danmaku_staff_bypass).returns(true)
    SiteSetting.stubs(:danmaku_premium_group_names_map).returns([premium_group.id])
    SiteSetting.stubs(:danmaku_send_rate_limit_seconds).returns(0)
    SiteSetting.stubs(:danmaku_daily_limit_per_user).returns(100)
  end

  def add_user_to_premium_group(target_user = user)
    GroupUser.create!(group: premium_group, user: target_user)
  end

  it "creates exactly one danmaku item for a premium opted-in post" do
    add_user_to_premium_group
    DiscourseDanmaku::Publisher.expects(:publish_create).once do |item|
      expect(item.source_post_id).to eq(source_post.id)
    end

    result = nil

    expect {
      result = described_class.call(post: source_post, opts: base_opts, user: user)
    }.to change(DiscourseDanmaku::Item, :count).by(1)

    item = DiscourseDanmaku::Item.last
    expect(result[:status]).to eq(:created)
    expect(result[:item]).to eq(item)
    expect(item.source_post_id).to eq(source_post.id)
    expect(item.topic_id).to eq(topic.id)
    expect(item.target_post_id).to eq(same_topic_target_post.id)
    expect(item.user_id).to eq(user.id)
    expect(item.body).to eq("source snapshot")
    expect(item.mode).to eq("scroll")
    expect(item.color).to eq("#abc")
  end

  it "creates no danmaku item when the checkbox is not selected" do
    add_user_to_premium_group

    result = nil

    expect {
      result = described_class.call(post: source_post, opts: base_opts.merge(danmaku_enabled: false), user: user)
    }.not_to change(DiscourseDanmaku::Item, :count)

    expect(result[:status]).to eq(:not_opted_in)
  end

  it "preserves an explicit false symbol value instead of falling back to a string key" do
    add_user_to_premium_group

    result = nil

    expect {
      result = described_class.call(
        post: source_post,
        opts: { danmaku_enabled: false, "danmaku_enabled" => true },
        user: user
      )
    }.not_to change(DiscourseDanmaku::Item, :count)

    expect(result[:status]).to eq(:not_opted_in)
  end

  it "does not create danmaku for forged non-premium params and does not raise" do
    Rails.logger.expects(:warn).once
    result = nil

    expect {
      result = described_class.call(post: source_post, opts: base_opts, user: user)
    }.not_to change(DiscourseDanmaku::Item, :count)

    expect(result[:status]).to eq(:permission_denied)
  end

  it "adds a composer-visible error before post creation when opted-in user lacks permission" do
    unsaved_post = Fabricate.build(:post, topic: topic, user: user, raw: "source snapshot")

    described_class.validate_before_post_create(post: unsaved_post, opts: base_opts, user: user)

    expect(unsaved_post.errors[:base]).to include(I18n.t("danmaku.errors.premium_required"))
  end

  it "does not add a preflight error when the user can send danmaku" do
    add_user_to_premium_group
    unsaved_post = Fabricate.build(:post, topic: topic, user: user, raw: "source snapshot")

    described_class.validate_before_post_create(post: unsaved_post, opts: base_opts, user: user)

    expect(unsaved_post.errors[:base]).to be_blank
  end

  it "does not create duplicates for the same source post" do
    add_user_to_premium_group
    DiscourseDanmaku::Publisher.expects(:publish_create).never
    existing_item = DiscourseDanmaku::Item.create!(
      topic: topic,
      source_post: source_post,
      user: user,
      body: "existing snapshot"
    )

    result = nil

    expect {
      result = described_class.call(post: source_post, opts: base_opts, user: user)
    }.not_to change(DiscourseDanmaku::Item, :count)

    expect(result[:status]).to eq(:already_exists)
    expect(result[:item]).to eq(existing_item)
  end

  it "rejects invalid mode values without creating an item" do
    add_user_to_premium_group

    result = nil

    expect {
      result = described_class.call(post: source_post, opts: base_opts.merge(danmaku_mode: "middle"), user: user)
    }.not_to change(DiscourseDanmaku::Item, :count)

    expect(result[:status]).to eq(:invalid_mode)
  end

  it "rejects invalid color values without creating an item" do
    add_user_to_premium_group

    result = nil

    expect {
      result = described_class.call(post: source_post, opts: base_opts.merge(danmaku_color: "red"), user: user)
    }.not_to change(DiscourseDanmaku::Item, :count)

    expect(result[:status]).to eq(:invalid_color)
  end

  it "accepts color values with alpha transparency" do
    add_user_to_premium_group

    result = nil

    expect {
      result = described_class.call(post: source_post, opts: base_opts.merge(danmaku_color: "#ffeb3b80"), user: user)
    }.to change(DiscourseDanmaku::Item, :count).by(1)

    item = DiscourseDanmaku::Item.last
    expect(result[:status]).to eq(:created)
    expect(item.color).to eq("#ffeb3b80")
  end

  it "returns body_too_long before item creation when the source body exceeds the configured limit" do
    add_user_to_premium_group
    SiteSetting.stubs(:danmaku_max_text_length).returns(5)

    result = nil

    expect {
      result = described_class.call(post: source_post, opts: base_opts, user: user)
    }.not_to change(DiscourseDanmaku::Item, :count)

    expect(result[:status]).to eq(:body_too_long)
  end

  it "allows blank color and defaults a blank mode to scroll" do
    add_user_to_premium_group

    result = nil

    expect {
      result = described_class.call(
        post: source_post,
        opts: base_opts.merge(danmaku_mode: "", danmaku_color: ""),
        user: user
      )
    }.to change(DiscourseDanmaku::Item, :count).by(1)

    item = DiscourseDanmaku::Item.last
    expect(result[:status]).to eq(:created)
    expect(item.mode).to eq("scroll")
    expect(item.color).to be_nil
  end

  it "drops target_post_id when the target is outside the source topic" do
    add_user_to_premium_group

    result = nil

    expect {
      result = described_class.call(
        post: source_post,
        opts: base_opts.merge(danmaku_target_post_id: other_topic_target_post.id),
        user: user
      )
    }.to change(DiscourseDanmaku::Item, :count).by(1)

    expect(result[:status]).to eq(:created)
    expect(result[:item].target_post_id).to be_nil
  end

  it "drops target_post_id when the viewer cannot see the target post" do
    add_user_to_premium_group
    hidden_target = Post.find(same_topic_target_post.id)
    hidden_target.stubs(:trashed?).returns(true)
    Post.stubs(:find_by).with(id: same_topic_target_post.id).returns(hidden_target)

    result = nil

    expect {
      result = described_class.call(post: source_post, opts: base_opts, user: user)
    }.to change(DiscourseDanmaku::Item, :count).by(1)

    expect(result[:status]).to eq(:created)
    expect(result[:item].target_post_id).to be_nil
  end

  it "does not create a danmaku item for an excluded category" do
    add_user_to_premium_group
    DiscourseDanmaku::Publisher.expects(:publish_create).never
    SiteSetting.stubs(:danmaku_excluded_category_ids).returns("#{topic.category_id}|999")

    result = nil

    expect {
      result = described_class.call(post: source_post, opts: base_opts, user: user)
    }.not_to change(DiscourseDanmaku::Item, :count)

    expect(result[:status]).to eq(:permission_denied)
  end

  it "returns plugin_disabled early when the plugin setting is off" do
    add_user_to_premium_group
    DiscourseDanmaku::Publisher.expects(:publish_create).never
    SiteSetting.stubs(:danmaku_enabled).returns(false)

    result = described_class.call(post: source_post, opts: base_opts, user: user)

    expect(result[:status]).to eq(:plugin_disabled)
  end
end
