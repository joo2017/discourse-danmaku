# frozen_string_literal: true

require "rails_helper"

RSpec.describe DiscourseDanmaku::Item, type: :model do
  fab!(:topic)
  fab!(:user)
  fab!(:source_post) { Fabricate(:post, topic: topic, user: user) }
  fab!(:target_post) { Fabricate(:post, topic: topic) }

  def build_item(attrs = {})
    described_class.new(
      {
        topic: topic,
        target_post: target_post,
        source_post: source_post,
        user: user,
        body: "danmaku body",
        mode: "scroll",
        color: "#abc",
        status: "visible"
      }.merge(attrs)
    )
  end

  it "is valid with the required associations and attributes" do
    expect(build_item).to be_valid
  end

  it "allows a missing target_post because it is only contextual" do
    expect(build_item(target_post: nil)).to be_valid
  end

  it "requires a source_post for the reply-linked create flow" do
    item = build_item(source_post: nil)

    expect(item).not_to be_valid
    expect(item.errors[:source_post]).to be_present
  end

  it "rejects a blank body" do
    item = build_item(body: "")

    expect(item).not_to be_valid
    expect(item.errors[:body]).to be_present
  end

  it "rejects a body longer than the configured max length" do
    SiteSetting.stubs(:danmaku_max_text_length).returns(5)
    item = build_item(body: "toolong")

    expect(item).not_to be_valid
    expect(item.errors[:body]).to include(I18n.t("errors.messages.too_long", count: 5))
  end

  it "rejects an invalid mode" do
    item = build_item(mode: "middle")

    expect(item).not_to be_valid
    expect(item.errors[:mode]).to be_present
  end

  it "rejects an invalid color" do
    item = build_item(color: "red")

    expect(item).not_to be_valid
    expect(item.errors[:color]).to be_present
  end

  it "accepts blank color and valid hex color values" do
    expect(build_item(color: nil)).to be_valid
    expect(build_item(color: "#a1b2c3")).to be_valid
    expect(build_item(color: "#a1b2c380")).to be_valid
  end

  it "rejects an invalid status" do
    item = build_item(status: "archived")

    expect(item).not_to be_valid
    expect(item.errors[:status]).to be_present
  end

  it "rejects negative count values" do
    item = build_item(likes_count: -1, replies_count: -1)

    expect(item).not_to be_valid
    expect(item.errors[:likes_count]).to be_present
    expect(item.errors[:replies_count]).to be_present
  end

  it "persists database defaults for mode, counts, and status" do
    item = described_class.create!(
      topic: topic,
      source_post: source_post,
      user: user,
      body: "snapshot"
    )

    expect(item.reload.mode).to eq("scroll")
    expect(item.likes_count).to eq(0)
    expect(item.replies_count).to eq(0)
    expect(item.status).to eq("visible")
  end

  it "enforces source_post uniqueness when present" do
    described_class.create!(
      topic: topic,
      source_post: source_post,
      user: user,
      body: "first"
    )

    duplicate = build_item(body: "second", target_post: nil)

    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:source_post_id]).to be_present
  end

  it "declares the expected associations" do
    target_post_reflection = described_class.reflect_on_association(:target_post)
    source_post_reflection = described_class.reflect_on_association(:source_post)

    expect(described_class.reflect_on_association(:topic).klass).to eq(Topic)
    expect(target_post_reflection.klass).to eq(Post)
    expect(target_post_reflection.options[:optional]).to eq(true)
    expect(source_post_reflection.klass).to eq(Post)
    expect(described_class.reflect_on_association(:user).klass).to eq(User)
  end
end
