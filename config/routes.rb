# frozen_string_literal: true

DiscourseDanmaku::Engine.routes.draw do
  get "/items/global" => "items#global"

  resources :items, only: %i[index show] do
    member do
      post :like
      delete :like, action: :unlike
      post :hide
    end
  end
end

Discourse::Application.routes.draw do
  mount ::DiscourseDanmaku::Engine, at: "/danmaku"
end
