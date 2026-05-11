# frozen_string_literal: true

module DiscourseDanmaku
  module PostCreatorExtension
    module_function

    def call(post:, opts:, user:)
      PostCreation.call(post: post, opts: opts, user: user)
    end

    def validate_before_post_create(post:, opts:, user:)
      PostCreation.validate_before_post_create(post: post, opts: opts, user: user)
    end
  end
end
