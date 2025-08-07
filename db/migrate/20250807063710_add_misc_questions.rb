class AddMiscQuestions < ActiveRecord::Migration[8.0]
  def change
    add_column :surveys, :misc, :json, null: false, default: []
    change_column :surveys, :misc, :json, default: nil
  end
end
