# frozen_string_literal: true

require "rails_helper"

RSpec.describe DiscourseDanmaku::Permissions do
  fab!(:topic)
  fab!(:user)
  fab!(:other_user)
  fab!(:premium_group) { Fabricate(:group, name: "danmaku_premium") }
  fab!(:source_post) { Fabricate(:post, topic: topic, user: user) }
  fab!(:other_source_post) { Fabricate(:post, topic: topic, user: other_user) }
  let(:item) do
    DiscourseDanmaku::Item.create!(
      topic: topic,
      source_post: source_post,
      user: user,
      body: "snapshot"
    )
  end

  let(:guardian) { Guardian.new(user) }
  let(:anonymous_guardian) { Guardian.new(nil) }

  before do
    SiteSetting.stubs(:danmaku_enabled).returns(true)
    SiteSetting.stubs(:danmaku_global_public_only).returns(true)
    SiteSetting.stubs(:danmaku_staff_bypass).returns(true)
    SiteSetting.stubs(:danmaku_premium_group_names_map).returns([premium_group.id])
    SiteSetting.stubs(:danmaku_send_rate_limit_seconds).returns(10)
    SiteSetting.stubs(:danmaku_daily_limit_per_user).returns(100)
  end

  def add_user_to_premium_group(target_user = user)
    GroupUser.create!(group: premium_group, user: target_user)
  end

  it "allows premium-group members to use premium tools and send" do
    add_user_to_premium_group

    expect(described_class.can_use_premium_tools?(user: user)).to eq(true)
    expect(described_class.can_send?(user: user, guardian: guardian, source_post: source_post)).to eq(true)
  end

  it "denies premium tools and send for non-members" do
    expect(described_class.can_use_premium_tools?(user: user)).to eq(false)
    expect(described_class.can_send?(user: user, guardian: guardian, source_post: source_post)).to eq(false)
  end

  it "reads mapped premium group ids from the site setting helper" do
    expect(described_class.premium_group_ids).to eq([premium_group.id])
  end

  it "ignores invalid mapped group ids instead of treating everyone as premium" do
    SiteSetting.stubs(:danmaku_premium_group_names_map).returns([0, "", premium_group.id])

    expect(described_class.premium_group_ids).to eq([premium_group.id])
    expect(described_class.can_use_premium_tools?(user: user)).to eq(false)
  end

  it "parses excluded category ids from delimited strings and arrays" do
    SiteSetting.stubs(:danmaku_excluded_category_ids).returns("#{topic.category_id}|45,78")

    expect(described_class.excluded_category_ids).to eq([topic.category_id, 45, 78])

    SiteSetting.stubs(:danmaku_excluded_category_ids).returns([topic.category_id.to_s, "", 45])

    expect(described_class.excluded_category_ids).to eq([topic.category_id, 45])
  end

  it "refreshes cached excluded category ids when the setting value changes" do
    SiteSetting.stubs(:danmaku_excluded_category_ids).returns("1|2")
    expect(described_class.excluded_category_ids).to eq([1, 2])

    SiteSetting.stubs(:danmaku_excluded_category_ids).returns("3,4")
    expect(described_class.excluded_category_ids).to eq([3, 4])
  end

  it "allows staff bypass when enabled" do
    staff_user = Fabricate(:admin)

    expect(described_class.can_use_premium_tools?(user: staff_user)).to eq(true)
  end

  it "denies staff bypass when the setting is off and the staff user is not in a premium group" do
    staff_user = Fabricate(:admin)
    SiteSetting.stubs(:danmaku_staff_bypass).returns(false)

    expect(described_class.can_use_premium_tools?(user: staff_user)).to eq(false)
  end

  it "lets anonymous guardians view visible public items but not send or like" do
    expect(described_class.can_view_item?(guardian: anonymous_guardian, item: item)).to eq(true)
    expect(described_class.can_send?(user: nil, guardian: anonymous_guardian, source_post: source_post)).to eq(false)
    expect(described_class.can_like?(user: nil, guardian: anonymous_guardian, item: item)).to eq(false)
  end

  it "denies viewing a source when Guardian cannot see the topic or post" do
    denied_guardian = Guardian.new(user)
    denied_guardian.stubs(:can_see?).returns(false)

    expect(described_class.can_view_source?(guardian: denied_guardian, topic: topic, post: source_post)).to eq(false)
    expect(described_class.can_view_item?(guardian: denied_guardian, item: item)).to eq(false)
  end

  it "denies hidden and deleted items even when the viewer can otherwise see the source" do
    hidden_item = DiscourseDanmaku::Item.create!(
      topic: topic,
      source_post: Fabricate(:post, topic: topic, user: user),
      user: user,
      body: "hidden snapshot",
      status: "hidden"
    )
    deleted_item = DiscourseDanmaku::Item.create!(
      topic: topic,
      source_post: Fabricate(:post, topic: topic, user: user),
      user: user,
      body: "deleted snapshot",
      status: "deleted"
    )

    expect(described_class.can_view_item?(guardian: guardian, item: hidden_item)).to eq(false)
    expect(described_class.can_view_item?(guardian: guardian, item: deleted_item)).to eq(false)
    expect(described_class.can_like?(user: user, guardian: guardian, item: hidden_item)).to eq(false)
  end

  it "follows Discourse like rules by denying likes on the current user's own danmaku" do
    other_item = DiscourseDanmaku::Item.create!(topic: topic, source_post: other_source_post, user: other_user, body: "other snapshot")

    expect(described_class.can_like?(user: user, guardian: guardian, item: item)).to eq(false)
    expect(described_class.can_like?(user: user, guardian: guardian, item: other_item)).to eq(true)
    expect(described_class.can_unlike?(user: user, guardian: guardian, item: item)).to eq(true)
  end

  it "denies viewing and interaction when the plugin is disabled" do
    add_user_to_premium_group
    SiteSetting.stubs(:danmaku_enabled).returns(false)

    expect(described_class.can_view_item?(guardian: guardian, item: item)).to eq(false)
    expect(described_class.can_send?(user: user, guardian: guardian, source_post: source_post)).to eq(false)
    expect(described_class.can_use_premium_tools?(user: user)).to eq(false)
    expect(described_class.can_like?(user: user, guardian: guardian, item: item)).to eq(false)
  end

  it "denies send for suspended users" do
    add_user_to_premium_group
    user.stubs(:suspended?).returns(true)

    expect(described_class.can_send?(user: user, guardian: guardian, source_post: source_post)).to eq(false)
  end

  it "denies send for silenced users" do
    add_user_to_premium_group
    user.stubs(:silenced?).returns(true)

    expect(described_class.can_send?(user: user, guardian: guardian, source_post: source_post)).to eq(false)
  end

  it "enforces the cooldown using the configured site setting" do
    add_user_to_premium_group
    item.update_columns(created_at: 5.seconds.ago, updated_at: 5.seconds.ago)

    expect(described_class.cooldown_active?(user: user)).to eq(true)
    expect(described_class.can_send?(user: user, guardian: guardian, source_post: source_post)).to eq(false)
  end

  it "enforces the daily cap using the configured site setting" do
    add_user_to_premium_group
    SiteSetting.stubs(:danmaku_send_rate_limit_seconds).returns(0)
    SiteSetting.stubs(:danmaku_daily_limit_per_user).returns(2)
    item.update_columns(created_at: 2.hours.ago, updated_at: 2.hours.ago)

    second_post = Fabricate(:post, topic: topic, user: user)
    DiscourseDanmaku::Item.create!(topic: topic, source_post: second_post, user: user, body: "second")

    expect(described_class.daily_cap_reached?(user: user)).to eq(true)
    expect(described_class.can_send?(user: user, guardian: guardian, source_post: source_post)).to eq(false)
  end

  it "requires public visibility when the global public-only stream setting is enabled" do
    add_user_to_premium_group
    DiscourseDanmaku::Permissions.stubs(:publicly_visible_topic?).with(topic: topic).returns(true)
    DiscourseDanmaku::Permissions.stubs(:publicly_visible_post?).with(post: source_post).returns(false)

    expect(described_class.can_view_source?(guardian: guardian, topic: topic, post: source_post)).to eq(true)
    expect(described_class.globally_visible_source?(topic: topic, post: source_post)).to eq(false)
  end

  it "allows non-public content for authorized viewers when the global public-only setting is disabled" do
    SiteSetting.stubs(:danmaku_global_public_only).returns(false)
    DiscourseDanmaku::Permissions.stubs(:publicly_visible_topic?).with(topic: topic).returns(true)
    DiscourseDanmaku::Permissions.stubs(:publicly_visible_post?).with(post: source_post).returns(false)

    expect(described_class.can_view_source?(guardian: guardian, topic: topic, post: source_post)).to eq(true)
    expect(described_class.can_view_item?(guardian: guardian, item: item)).to eq(true)
    expect(described_class.globally_visible_source?(topic: topic, post: source_post)).to eq(true)
  end

  it "keeps topic-local reads, likes, and sends available to authorized viewers when public-only global filtering is enabled" do
    add_user_to_premium_group
    DiscourseDanmaku::Permissions.stubs(:publicly_visible_topic?).with(topic: topic).returns(true)
    DiscourseDanmaku::Permissions.stubs(:publicly_visible_post?).with(post: source_post).returns(false)
    other_item = DiscourseDanmaku::Item.create!(topic: topic, source_post: other_source_post, user: other_user, body: "other snapshot")

    expect(described_class.can_view_item?(guardian: guardian, item: item)).to eq(true)
    expect(described_class.can_like?(user: user, guardian: guardian, item: item)).to eq(false)
    expect(described_class.can_like?(user: user, guardian: guardian, item: other_item)).to eq(true)
    expect(described_class.can_send?(user: user, guardian: guardian, source_post: source_post)).to eq(true)
    expect(described_class.globally_visible_source?(topic: topic, post: source_post)).to eq(false)
  end

  it "allows global hide invalidation checks for once-public topics when only the source post became unavailable" do
    source_post.stubs(:hidden?).returns(true)
    DiscourseDanmaku::Permissions.stubs(:publicly_visible_topic?).with(topic: topic).returns(true)
    DiscourseDanmaku::Permissions.stubs(:publicly_visible_post?).with(post: source_post).returns(false)

    expect(described_class.globally_visible_source?(topic: topic, post: source_post, allow_unavailable: true)).to eq(true)
  end

  it "still denies global hide invalidation checks for restricted topics when allow_unavailable is enabled" do
    source_post.stubs(:hidden?).returns(true)
    DiscourseDanmaku::Permissions.stubs(:publicly_visible_topic?).with(topic: topic).returns(false)

    expect(described_class.globally_visible_source?(topic: topic, post: source_post, allow_unavailable: true)).to eq(false)
  end

  it "delegates cleanly through Guardian extension helpers" do
    add_user_to_premium_group
    other_item = DiscourseDanmaku::Item.create!(topic: topic, source_post: other_source_post, user: other_user, body: "other snapshot")

    expect(guardian.can_view_danmaku_source?(topic, source_post)).to eq(true)
    expect(guardian.can_send_danmaku?(source_post)).to eq(true)
    expect(guardian.can_use_danmaku_premium_tools?).to eq(true)
    expect(guardian.can_view_danmaku_item?(item)).to eq(true)
    expect(guardian.can_like_danmaku?(other_item)).to eq(true)
    expect(guardian.can_moderate_danmaku?).to eq(false)
  end

  it "allows staff users to moderate danmaku items" do
    staff_user = Fabricate(:admin)

    expect(described_class.can_moderate?(user: staff_user)).to eq(true)
    expect(Guardian.new(staff_user).can_moderate_danmaku?).to eq(true)
  end
end
