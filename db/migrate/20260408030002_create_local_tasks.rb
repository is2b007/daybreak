class CreateLocalTasks < ActiveRecord::Migration[8.1]
  def change
    create_table :local_tasks do |t|
      t.references :user, null: false, foreign_key: true
      t.string :title, null: false
      t.text :description

      t.timestamps
    end
  end
end
