# frozen_string_literal: true

require "rails_helper"

RSpec.describe DiscourseDanmaku::ItemLikeSynchronizer do
  fab!(:topic)
  fab!(:user)
  fab!(:other_user)
  fab!(:source_post) { Fabricate(:post, topic: topic, user: other_user) }
  fab!(:item) { DiscourseDanmaku::Item.create!(topic: topic, source_post: source_post, user: other_user, body: "sync me") }

  let(:guardian) { Guardian.new(user) }

  before do
    SiteSetting.stubs(:danmaku_enabled).returns(true)
  end

  it "likes idempotently, syncs the source post once, and publishes only on mutation" do
    DiscourseDanmaku::Publisher.expects(:publish_like).once

    described_class.like!(item: item, user: user, guardian: guardian)
    described_class.like!(item: item.reload, user: user, guardian: guardian)

    expect(DiscourseDanmaku::Like.where(item: item, user: user).count).to eq(1)
    expect(item.reload.likes_count).to eq(1)
    expect(source_post.reload.like_count).to eq(1)
  end

  it "unlikes idempotently, removes the synced source post like once, and publishes only on mutation" do
    described_class.like!(item: item, user: user, guardian: guardian)
    DiscourseDanmaku::Publisher.expects(:publish_like).once

    described_class.unlike!(item: item.reload, user: user, guardian: guardian)
    described_class.unlike!(item: item.reload, user: user, guardian: guardian)

    expect(DiscourseDanmaku::Like.where(item: item, user: user).count).to eq(0)
    expect(item.reload.likes_count).to eq(0)
    expect(source_post.reload.like_count).to eq(0)
  end
end
