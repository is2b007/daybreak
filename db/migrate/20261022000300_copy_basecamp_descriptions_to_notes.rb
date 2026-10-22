class CopyBasecampDescriptionsToNotes < ActiveRecord::Migration[8.1]
  # Before `notes` existed, users typed their own notes into `description` on
  # Basecamp tasks. Sync now owns `description`, so carry that text over before
  # the next sync replaces it.
  def up
    execute <<~SQL
      UPDATE task_assignments
      SET notes = description
      WHERE source = 1 AND notes IS NULL -- basecamp
        AND description IS NOT NULL AND description != ''
    SQL
  end

  def down
  end
end
