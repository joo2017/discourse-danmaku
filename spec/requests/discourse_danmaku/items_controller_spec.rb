# frozen_string_literal: true

require "rails_helper"

RSpec.describe "DiscourseDanmaku::ItemsController", type: :request do
  fab!(:topic)
  fab!(:user)
  fab!(:other_user)
  fab!(:staff_user) { Fabricate(:admin) }
  fab!(:source_post) { Fabricate(:post, topic: topic, user: user) }
  fab!(:second_source_post) { Fabricate(:post, topic: topic, user: other_user) }

  let!(:public_item) do
    DiscourseDanmaku::Item.create!(
      topic: topic,
      source_post: source_post,
      user: user,
      body: "public body"
    )
  end

  let!(:private_item) do
    DiscourseDanmaku::Item.create!(
      topic: topic,
      source_post: second_source_post,
      user: other_user,
      body: "private secret body"
    )
  end

  before do
    SiteSetting.stubs(:danmaku_enabled).returns(true)
    SiteSetting.stubs(:danmaku_initial_fetch_limit).returns(5)
    SiteSetting.stubs(:danmaku_global_public_only).returns(true)
    SiteSetting.stubs(:danmaku_staff_bypass).returns(true)

    allow(DiscourseDanmaku::Permissions).to receive(:can_view_item?) do |guardian:, item:|
      guardian.user.present? || item.id != private_item.id
    end
    allow(DiscourseDanmaku::Permissions).to receive(:globally_visible_source?) do |topic:, post:, allow_unavailable: false|
      post.id == source_post.id
    end
    allow(DiscourseDanmaku::Permissions).to receive(:can_like?) do |user:, guardian:, item:|
      user.present? && (item.id == public_item.id || item.id == private_item.id)
    end
    allow(DiscourseDanmaku::Permissions).to receive(:category_excluded?).and_return(false)
  end

  def parsed_body
    JSON.parse(response.body)
  end

  it "returns only public-visible items from the global index without leaking restricted bodies" do
    get "/danmaku/items/global", params: { after_id: 0, limit: 5 }

    expect(response.status).to eq(200)
    expect(parsed_body["items"].map { |item| item["id"] }).to eq([public_item.id])
    expect(response.body).to include("public body")
    expect(response.body).not_to include("private secret body")
  end

  it "still excludes restricted items from the global index for an authorized signed-in viewer" do
    sign_in(user)

    get "/danmaku/items/global", params: { after_id: 0, limit: 5 }

    expect(response.status).to eq(200)
    expect(parsed_body["items"].map { |item| item["id"] }).to eq([public_item.id])
    expect(response.body).not_to include("private secret body")
  end

  it "returns both public and topic-local authorized items when the current user can see the topic" do
    sign_in(user)

    get "/danmaku/items", params: { topic_id: topic.id, after_id: 0, limit: 5 }

    expect(response.status).to eq(200)
    expect(parsed_body["items"].map { |item| item["id"] }).to eq([public_item.id, private_item.id])
  end

  it "batches current-user liked state for item lists" do
    sign_in(user)
    DiscourseDanmaku::Like.create!(item: private_item, user: user)

    get "/danmaku/items", params: { topic_id: topic.id, after_id: 0, limit: 5 }

    liked_by_id = parsed_body["items"].index_by { |item| item["id"] }.transform_values { |item| item["liked_by_current_user"] }
    expect(liked_by_id).to include(public_item.id => false, private_item.id => true)
  end

  it "denies the topic index when the current user cannot see the topic" do
    sign_in(user)
    allow_any_instance_of(Guardian).to receive(:can_see?) do |_, record|
      record != topic
    end

    get "/danmaku/items", params: { topic_id: topic.id }

    expect(response.status).to eq(403)
  end

  it "does not fall back to global results when a topic_id is provided but the topic does not exist" do
    sign_in(user)

    get "/danmaku/items", params: { topic_id: 999_999, after_id: 0, limit: 5 }

    expect([403, 404]).to include(response.status)
    expect(response.body).not_to include("public body")
    expect(response.body).not_to include("private secret body")
  end

  it "shows a visible item" do
    get "/danmaku/items/#{public_item.id}"

    expect(response.status).to eq(200)
    expect(parsed_body.dig("item", "id")).to eq(public_item.id)
    expect(parsed_body.dig("item", "body")).to eq("public body")
  end

  it "lets an authorized signed-in viewer read a topic-local item that is excluded from the anonymous global stream" do
    sign_in(user)

    get "/danmaku/items/#{private_item.id}"

    expect(response.status).to eq(200)
    expect(parsed_body.dig("item", "id")).to eq(private_item.id)
    expect(parsed_body.dig("item", "body")).to eq("private secret body")
  end

  it "returns not found for an inaccessible item without leaking the body" do
    get "/danmaku/items/#{private_item.id}"

    expect(response.status).to eq(404)
    expect(response.body).not_to include("private secret body")
  end

  it "returns not found for hidden items without leaking the body" do
    public_item.update!(status: "hidden")

    get "/danmaku/items/#{public_item.id}"

    expect(response.status).to eq(404)
    expect(response.body).not_to include("public body")
  end

  it "clamps index responses to the configured initial fetch limit" do
    SiteSetting.stubs(:danmaku_initial_fetch_limit).returns(1)
    sign_in(user)

    get "/danmaku/items", params: { limit: 50 }

    expect(response.status).to eq(200)
    expect(parsed_body["items"].length).to eq(1)
  end

  it "clamps global responses to the configured initial fetch limit" do
    SiteSetting.stubs(:danmaku_initial_fetch_limit).returns(1)

    get "/danmaku/items/global", params: { limit: 50 }

    expect(response.status).to eq(200)
    expect(parsed_body["items"].map { |item| item["id"] }).to eq([public_item.id])
  end

  it "applies a hard server-side cap even when the configured fetch limit is high" do
    SiteSetting.stubs(:danmaku_initial_fetch_limit).returns(500)
    sign_in(user)

    120.times do |index|
      post = Fabricate(:post, topic: topic, user: user)
      DiscourseDanmaku::Item.create!(topic: topic, source_post: post, user: user, body: "bulk #{index}")
    end

    get "/danmaku/items", params: { topic_id: topic.id, limit: 999 }

    expect(response.status).to eq(200)
    expect(parsed_body["items"].length).to eq(DiscourseDanmaku::ItemsController::MAX_FETCH_LIMIT)
  end

  it "likes an item idempotently" do
    sign_in(user)
    DiscourseDanmaku::Publisher.expects(:publish_like).once do |item|
      expect(item.id).to eq(public_item.id)
      expect(item.source_post_id).to eq(source_post.id)
    end

    post "/danmaku/items/#{public_item.id}/like"
    post "/danmaku/items/#{public_item.id}/like"

    expect(response.status).to eq(200)
    expect(DiscourseDanmaku::Like.where(item: public_item, user: user).count).to eq(1)
    expect(public_item.reload.likes_count).to eq(1)
    expect(parsed_body.dig("item", "liked_by_current_user")).to eq(true)
    expect(source_post.reload.like_count).to eq(0)
  end

  it "lets an authorized signed-in viewer like a topic-local item that stays out of the anonymous global stream" do
    sign_in(user)
    DiscourseDanmaku::Publisher.expects(:publish_like).once do |item|
      expect(item.id).to eq(private_item.id)
      expect(item.source_post_id).to eq(second_source_post.id)
    end

    post "/danmaku/items/#{private_item.id}/like"

    expect(response.status).to eq(200)
    expect(DiscourseDanmaku::Like.where(item: private_item, user: user).count).to eq(1)
    expect(private_item.reload.likes_count).to eq(1)
    expect(second_source_post.reload.like_count).to eq(1)
    expect(
      PostAction.exists?(
        user_id: user.id,
        post_id: second_source_post.id,
        post_action_type_id: PostActionType.types[:like]
      )
    ).to eq(true)
  end

  it "unlikes an item and removes the synced source post like" do
    sign_in(user)
    DiscourseDanmaku::Publisher.expects(:publish_like).twice

    post "/danmaku/items/#{private_item.id}/like"
    delete "/danmaku/items/#{private_item.id}/like"
    delete "/danmaku/items/#{private_item.id}/like"

    expect(response.status).to eq(200)
    expect(DiscourseDanmaku::Like.where(item: private_item, user: user).count).to eq(0)
    expect(private_item.reload.likes_count).to eq(0)
    expect(parsed_body.dig("item", "liked_by_current_user")).to eq(false)
    expect(second_source_post.reload.like_count).to eq(0)
    expect(
      PostAction.exists?(
        user_id: user.id,
        post_id: second_source_post.id,
        post_action_type_id: PostActionType.types[:like]
      )
    ).to eq(false)
  end

  it "rejects anonymous like attempts" do
    post "/danmaku/items/#{public_item.id}/like"

    expect(response.status).to eq(403)
    expect(public_item.reload.likes_count).to eq(0)
  end

  it "rejects like attempts when Discourse-like permissions deny the action" do
    sign_in(user)
    allow(DiscourseDanmaku::Permissions).to receive(:can_like?).and_return(false)
    DiscourseDanmaku::Publisher.expects(:publish_like).never

    post "/danmaku/items/#{public_item.id}/like"

    expect(response.status).to eq(403)
    expect(DiscourseDanmaku::Like.where(item: public_item, user: user).count).to eq(0)
    expect(public_item.reload.likes_count).to eq(0)
  end

  it "still allows existing likes to be removed when like permission later denies new likes" do
    sign_in(user)
    DiscourseDanmaku::Like.create!(item: public_item, user: user)
    public_item.update!(likes_count: 1)
    allow(DiscourseDanmaku::Permissions).to receive(:can_like?).and_return(false)
    allow(DiscourseDanmaku::Permissions).to receive(:can_unlike?).and_return(true)
    DiscourseDanmaku::Publisher.expects(:publish_like).once

    delete "/danmaku/items/#{public_item.id}/like"

    expect(response.status).to eq(200)
    expect(DiscourseDanmaku::Like.where(item: public_item, user: user).count).to eq(0)
    expect(public_item.reload.likes_count).to eq(0)
  end

  it "lets staff hide an item" do
    sign_in(staff_user)
    DiscourseDanmaku::Publisher.expects(:publish_hide).once do |item|
      expect(item.id).to eq(public_item.id)
      expect(item.status).to eq("deleted")
    end

    post "/danmaku/items/#{public_item.id}/hide", params: { status: "deleted" }

    expect(response.status).to eq(200)
    expect(public_item.reload.status).to eq("deleted")
    expect(parsed_body.dig("item", "status")).to eq("deleted")
  end

  it "rejects hide for non-staff users" do
    sign_in(user)
    DiscourseDanmaku::Publisher.expects(:publish_hide).never

    post "/danmaku/items/#{public_item.id}/hide"

    expect(response.status).to eq(403)
    expect(public_item.reload.status).to eq("visible")
  end

  it "prevents controller access when the plugin setting is disabled" do
    SiteSetting.stubs(:danmaku_enabled).returns(false)

    get "/danmaku/items/global"

    expect(response.status).not_to eq(200)
    expect(response.body).not_to include("public body")
    expect(response.body).not_to include("private secret body")
  end
end
