# frozen_string_literal: true

class AddDiscourseDanmakuSenderTimeIndex < ActiveRecord::Migration[7.0]
  def change
    # Intentionally left blank.
    #
    # The existing user_id index is sufficient for correctness. Keep this
    # migration version so sites that already pulled it can advance cleanly.
  end
end
