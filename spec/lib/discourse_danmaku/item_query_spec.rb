# frozen_string_literal: true

require "rails_helper"

RSpec.describe DiscourseDanmaku::ItemQuery do
  fab!(:topic)
  fab!(:user)
  fab!(:source_post) { Fabricate(:post, topic: topic, user: user) }

  before do
    SiteSetting.stubs(:danmaku_enabled).returns(true)
    SiteSetting.stubs(:danmaku_global_public_only).returns(true)
  end

  def create_item(body:, post: Fabricate(:post, topic: topic, user: user), status: "visible")
    DiscourseDanmaku::Item.create!(topic: topic, source_post: post, user: user, body: body, status: status)
  end

  it "continues scanning until it fills the requested visible page" do
    hidden_by_guard = create_item(body: "denied")
    first_allowed = create_item(body: "allowed 1")
    second_allowed = create_item(body: "allowed 2")

    items =
      described_class.list(
        base_scope: described_class.base_scope,
        after_id: 0,
        limit: 2,
        visibility_check: ->(item) { item.id != hidden_by_guard.id }
      )

    expect(items.map(&:id)).to eq([first_allowed.id, second_allowed.id])
  end

  it "returns the latest visible page for initial global loads" do
    create_item(body: "old")
    middle = create_item(body: "middle")
    latest = create_item(body: "latest")

    items =
      described_class.list(
        base_scope: described_class.base_scope,
        after_id: 0,
        limit: 2,
        visibility_check: ->(_item) { true }
      )

    expect(items.map(&:id)).to eq([middle.id, latest.id])
  end

  it "keeps topic-scoped pagination on visible items after an after_id cursor" do
    old = create_item(body: "old")
    hidden = create_item(body: "hidden", status: "hidden")
    visible = create_item(body: "visible")

    items =
      described_class.list(
        base_scope: described_class.base_scope.where(topic_id: topic.id),
        after_id: old.id,
        limit: 1,
        visibility_check: ->(_item) { true }
      )

    expect(items.map(&:id)).to eq([visible.id])
    expect(items.map(&:id)).not_to include(hidden.id)
  end

  it "keeps global visibility fail-closed for missing source context" do
    item = create_item(body: "orphaned")
    item.source_post = nil

    expect(described_class.globally_visible?(item)).to eq(false)
  end

  it "delegates global visibility to permission checks for valid source context" do
    item = create_item(body: "global", post: source_post)
    DiscourseDanmaku::Permissions.expects(:category_excluded?).with(topic).returns(false)
    DiscourseDanmaku::Permissions.expects(:globally_visible_source?).with(topic: topic, post: source_post).returns(true)

    expect(described_class.globally_visible?(item)).to eq(true)
  end
end
