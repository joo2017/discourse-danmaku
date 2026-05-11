# frozen_string_literal: true

class AddDiscourseDanmakuItemScanIndexes < ActiveRecord::Migration[7.0]
  def change
    # Intentionally left blank.
    #
    # These optional performance indexes were removed from the bootstrap path
    # after production rebuild failures at db:migrate. The base table migration
    # already creates the portable indexes needed for correctness.
  end
end
