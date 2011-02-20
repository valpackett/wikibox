require 'rubygems'
require 'sequel'

class Add_IndexFile < Sequel::Migration
  def up
    alter_table(:users) do
      add_column :indexfile, String
    end
  end
  def down
    alter_table(:users) do
      drop_column :indexfile
    end
  end
end
