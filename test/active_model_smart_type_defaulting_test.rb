require 'test_helper'
require 'action_controller/parameters'

class Column
  attr_accessor :name
  attr_accessor :klass
  def initialize(hsh)
    hsh.each do |name, klass|
      @name = name
      @klass = klass
    end
  end
end

class User
  def self.columns
    [Column.new("id" => Fixnum), Column.new("name" => String)]
  end
end

class ActiveModelSmartTypeDefaultingTest < ActiveSupport::TestCase
    test "if no types are given but the parent object shares a name with a model, attribute types are used" do
      params = ActionController::Parameters.new(:user => [:id => 1234])
      permitted = params.permit(:user => [:id, :name])
      assert_equal permitted[:user][0][:id], 1234
      assert_nil permitted[:user][0][:name]
    end
end
