# frozen_string_literal: true

require "rails_helper"

RSpec.describe DiscourseDanmaku::Publisher do
  fab!(:topic)
  fab!(:user)
  fab!(:source_post) { Fabricate(:post, topic: topic, user: user, raw: "source snapshot") }
  fab!(:item) do
    DiscourseDanmaku::Item.create!(
      topic: topic,
      source_post: source_post,
      user: user,
      body: "public body"
    )
  end

  let(:cache) { ActiveSupport::Cache::MemoryStore.new }
  let(:message_bus) { mock("message_bus") }
  let(:now) { Time.zone.parse("2026-04-24 12:34:00") }

  before do
    SiteSetting.stubs(:danmaku_enabled).returns(true)
    SiteSetting.stubs(:danmaku_global_public_only).returns(true)
    SiteSetting.stubs(:danmaku_excluded_category_ids).returns([])
    SiteSetting.stubs(:danmaku_global_broadcast_limit_per_minute).returns(5)
  end

  it "publishes create with the exact safe id-only payload" do
    payload = {
      type: "create",
      topic_id: topic.id,
      post_id: source_post.id,
      danmaku_id: item.id
    }

    message_bus.expects(:publish).with(described_class::CHANNEL, payload).once

    expect(described_class.publish_create(item, message_bus: message_bus, cache: cache, now: now)).to eq(true)
  end

  it "publishes only the safe payload even when the item has sensitive fields" do
    captured = []
    capturing_bus = Class.new do
      define_method(:publish) do |channel, payload|
        captured << [channel, payload]
      end
    end.new

    expect(described_class.publish_create(item, message_bus: capturing_bus, cache: cache, now: now)).to eq(true)
    expect(captured).to eq([[described_class::CHANNEL, { type: "create", topic_id: topic.id, post_id: source_post.id, danmaku_id: item.id }]])
    expect(captured.last.last.values.join(" ")).not_to include("public body")
    expect(captured.last.last.values.join(" ")).not_to include(user.username)
  end

  it "publishes like and hide with the same safe payload shape" do
    like_payload = {
      type: "like",
      topic_id: topic.id,
      post_id: source_post.id,
      danmaku_id: item.id
    }
    hide_payload = like_payload.merge(type: "hide")

    message_bus.expects(:publish).with(described_class::CHANNEL, like_payload).once
    message_bus.expects(:publish).with(described_class::CHANNEL, hide_payload).once

    expect(described_class.publish_like(item, message_bus: message_bus, cache: cache, now: now)).to eq(true)
    expect(described_class.publish_hide(item, message_bus: message_bus, cache: cache, now: now + 1.second)).to eq(true)
  end

  it "never includes sensitive fields in the payload" do
    payload = described_class.safe_payload(:create, item)

    expect(payload.keys).to contain_exactly(:type, :topic_id, :post_id, :danmaku_id)
    expect(payload).not_to have_key(:body)
    expect(payload).not_to have_key(:username)
    expect(payload).not_to have_key(:title)
    expect(payload).not_to have_key(:url)
    expect(payload).not_to have_key(:raw)
    expect(payload).not_to have_key(:cooked)
  end

  it "does not publish when the source is not public-visible" do
    DiscourseDanmaku::Permissions.stubs(:globally_visible_source?).returns(false)
    message_bus.expects(:publish).never

    expect(described_class.publish_create(item, message_bus: message_bus, cache: cache, now: now)).to eq(false)
  end

  it "publishes hide invalidations for public items even after the source becomes unavailable" do
    item.source_post.stubs(:hidden?).returns(true)
    DiscourseDanmaku::Permissions.stubs(:publicly_visible_topic?).with(topic: topic).returns(true)
    DiscourseDanmaku::Permissions.stubs(:publicly_visible_post?).with(post: source_post).returns(false)

    message_bus.expects(:publish).with(
      described_class::CHANNEL,
      { type: "hide", topic_id: topic.id, post_id: source_post.id, danmaku_id: item.id }
    ).once

    expect(
      described_class.publish_hide(item, message_bus: message_bus, cache: cache, now: now, allow_unavailable: true)
    ).to eq(true)
  end

  it "does not publish hide invalidations for restricted topics even when the source becomes unavailable" do
    item.source_post.stubs(:hidden?).returns(true)
    DiscourseDanmaku::Permissions.stubs(:publicly_visible_topic?).with(topic: topic).returns(false)
    message_bus.expects(:publish).never

    expect(
      described_class.publish_hide(item, message_bus: message_bus, cache: cache, now: now, allow_unavailable: true)
    ).to eq(false)
  end

  it "does not publish when the category is excluded" do
    DiscourseDanmaku::Permissions.stubs(:category_excluded?).with(topic).returns(true)
    message_bus.expects(:publish).never

    expect(described_class.publish_create(item, message_bus: message_bus, cache: cache, now: now)).to eq(false)
  end

  it "does not publish when the plugin setting is disabled" do
    SiteSetting.stubs(:danmaku_enabled).returns(false)
    message_bus.expects(:publish).never

    expect(described_class.publish_create(item, message_bus: message_bus, cache: cache, now: now)).to eq(false)
  end

  it "blocks publishes after the configured per-minute cap is reached" do
    SiteSetting.stubs(:danmaku_global_broadcast_limit_per_minute).returns(1)
    message_bus.expects(:publish).once

    expect(described_class.publish_create(item, message_bus: message_bus, cache: cache, now: now)).to eq(true)
    expect(described_class.publish_like(item, message_bus: message_bus, cache: cache, now: now + 5.seconds)).to eq(false)
  end

  it "uses cache increment for broadcast rate limiting when available" do
    SiteSetting.stubs(:danmaku_global_broadcast_limit_per_minute).returns(1)
    atomic_cache =
      Class.new do
        attr_reader :increments

        def initialize
          @counts = Hash.new(0)
          @increments = []
        end

        def increment(key, amount = 1, **options)
          @counts[key] += amount
          @increments << [key, amount, options]
          @counts[key]
        end

        def read(_key)
          raise "non-atomic read fallback should not be used"
        end

        def write(_key, _value, **_options)
          raise "non-atomic write fallback should not be used"
        end
      end.new

    message_bus.expects(:publish).once

    expect(described_class.publish_create(item, message_bus: message_bus, cache: atomic_cache, now: now)).to eq(true)
    expect(described_class.publish_like(item, message_bus: message_bus, cache: atomic_cache, now: now + 5.seconds)).to eq(false)
    expect(atomic_cache.increments.length).to eq(2)
    expect(atomic_cache.increments.first.last).to include(expires_in: 1.minute)
  end

  it "allows only one concurrent broadcast slot with an atomic cache" do
    SiteSetting.stubs(:danmaku_global_broadcast_limit_per_minute).returns(1)
    atomic_cache =
      Class.new do
        def initialize
          @counts = Hash.new(0)
          @mutex = Mutex.new
        end

        def increment(key, amount = 1, **_options)
          @mutex.synchronize do
            @counts[key] += amount
          end
        end
      end.new

    results =
      2.times.map do
        Thread.new { described_class.consume_broadcast_slot?(cache: atomic_cache, now: now) }
      end.map(&:value)

    expect(results.count(true)).to eq(1)
    expect(results.count(false)).to eq(1)
  end

  it "falls back to cache read and write when increment is unavailable" do
    SiteSetting.stubs(:danmaku_global_broadcast_limit_per_minute).returns(1)
    fallback_cache =
      Class.new do
        attr_reader :writes

        def initialize
          @count = nil
          @writes = []
        end

        def read(_key)
          @count
        end

        def write(key, value, **options)
          @count = value
          @writes << [key, value, options]
        end
      end.new

    expect(described_class.consume_broadcast_slot?(cache: fallback_cache, now: now)).to eq(true)
    expect(described_class.consume_broadcast_slot?(cache: fallback_cache, now: now)).to eq(false)
    expect(fallback_cache.writes.first.last).to include(expires_in: 1.minute)
  end

  it "falls back when cache increment returns nil" do
    SiteSetting.stubs(:danmaku_global_broadcast_limit_per_minute).returns(1)
    fallback_cache =
      Class.new do
        attr_reader :writes

        def initialize
          @count = nil
          @writes = []
        end

        def increment(_key, _amount = 1, **_options)
          nil
        end

        def read(_key)
          @count
        end

        def write(key, value, **options)
          @count = value
          @writes << [key, value, options]
        end
      end.new

    expect(described_class.consume_broadcast_slot?(cache: fallback_cache, now: now)).to eq(true)
    expect(fallback_cache.writes.length).to eq(1)
  end
end
