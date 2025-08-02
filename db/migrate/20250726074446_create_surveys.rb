class CreateSurveys < ActiveRecord::Migration[8.0]
  def change
    create_table :surveys do |t|
      t.integer :year, null: false
      t.string  :season, null: false
      t.string  :name, null: false
      t.string  :sheet_id, null: false
      t.string  :gid, null: false

      t.timestamps
    end
  end
end
