# frozen_string_literal: true

require "rails_helper"

RSpec.describe DiscourseDanmaku::ItemSerializer do
  fab!(:topic)
  fab!(:user)
  fab!(:source_post) { Fabricate(:post, topic: topic, user: user) }

  it "memoizes body visibility while serializing gated fields" do
    item =
      DiscourseDanmaku::Item.create!(
        topic: topic,
        source_post: source_post,
        user: user,
        body: "cached visibility"
      )
    guardian = Guardian.new(user)

    DiscourseDanmaku::Permissions.expects(:can_view_item?).with(guardian: guardian, item: item).once.returns(true)
    DiscourseDanmaku::Permissions.stubs(:can_like?).returns(false)

    payload = described_class.new(item, scope: guardian, root: false).as_json

    expect(payload[:body]).to eq("cached visibility")
    expect(payload[:source_topic_title]).to eq(topic.title)
    expect(payload[:source_topic_url]).to be_present
    expect(payload[:source_post_url]).to be_present
  end
end
