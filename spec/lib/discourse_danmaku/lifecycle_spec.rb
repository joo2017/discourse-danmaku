# frozen_string_literal: true

require "rails_helper"

RSpec.describe "DiscourseDanmaku lifecycle" do
  fab!(:topic)
  fab!(:user)
  fab!(:source_post) { Fabricate(:post, topic: topic, user: user, raw: "original body") }

  before do
    SiteSetting.stubs(:danmaku_enabled).returns(true)
  end

  it "hides associated items and publishes hide invalidations when the source post becomes hidden" do
    item = DiscourseDanmaku::Item.create!(
      topic: topic,
      source_post: source_post,
      user: user,
      body: "snapshot"
    )
    source_post.stubs(:hidden?).returns(true)
    DiscourseDanmaku::Publisher.expects(:publish_hide).with do |published_item, allow_unavailable:|
      expect(published_item.id).to eq(item.id)
      expect(published_item.status).to eq("hidden")
      expect(allow_unavailable).to eq(true)
    end.once

    affected_items = DiscourseDanmaku::Lifecycle.handle_source_post_change!(source_post)

    expect(affected_items.map(&:id)).to eq([item.id])
    expect(item.reload.status).to eq("hidden")
    expect(DiscourseDanmaku::Item.visible.where(id: item.id)).to be_empty
  end

  it "wires the runtime post_edited hook to the lifecycle service" do
    DiscourseDanmaku::Lifecycle.expects(:handle_source_post_change!).with(source_post).once

    DiscourseEvent.trigger(:post_edited, source_post)
  end

  it "wires the runtime post_destroyed hook to the lifecycle service" do
    DiscourseDanmaku::Lifecycle.expects(:handle_source_post_change!).with(source_post).once

    DiscourseEvent.trigger(:post_destroyed, source_post)
  end

  it "syncs the danmaku body when the source post body changes" do
    item = DiscourseDanmaku::Item.create!(
      topic: topic,
      source_post: source_post,
      user: user,
      body: "snapshot"
    )
    DiscourseDanmaku::Publisher.expects(:publish_create).with do |published_item|
      expect(published_item.id).to eq(item.id)
      expect(published_item.body).to eq("edited source body")
    end.once

    source_post.update!(raw: "edited source body")
    affected_items = DiscourseDanmaku::Lifecycle.handle_source_post_change!(source_post)

    expect(affected_items.map(&:id)).to eq([item.id])
    expect(item.reload.body).to eq("edited source body")
  end

  it "hides the danmaku when an edited source post exceeds the danmaku text limit" do
    SiteSetting.stubs(:danmaku_max_text_length).returns(10)
    item = DiscourseDanmaku::Item.create!(
      topic: topic,
      source_post: source_post,
      user: user,
      body: "snapshot"
    )
    DiscourseDanmaku::Publisher.expects(:publish_hide).with do |published_item, allow_unavailable:|
      expect(published_item.id).to eq(item.id)
      expect(published_item.status).to eq("hidden")
      expect(allow_unavailable).to eq(true)
    end.once

    source_post.update!(raw: "edited source body is too long")
    affected_items = DiscourseDanmaku::Lifecycle.handle_source_post_change!(source_post)

    expect(affected_items.map(&:id)).to eq([item.id])
    expect(item.reload.status).to eq("hidden")
  end

  it "keeps deleted items deleted when applying the hide lifecycle policy" do
    item = DiscourseDanmaku::Item.create!(
      topic: topic,
      source_post: source_post,
      user: user,
      body: "snapshot",
      status: "deleted"
    )

    hidden_count = DiscourseDanmaku::Permissions.hide_for_source_post!(source_post)

    expect(hidden_count).to eq(0)
    expect(item.reload.status).to eq("deleted")
  end
end
