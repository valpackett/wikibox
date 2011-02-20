require 'rubygems'
require 'sequel'

class Base < Sequel::Migration
  def up
    create_table! :users do
      primary_key :id
      String :email
      String :folder
    end
  end
  def down
    drop_table :users
  end
end
