require 'test_helper'
require 'action_controller/parameters'
require 'action_dispatch/http/upload'

class NestedParametersTest < ActiveSupport::TestCase
  def assert_filtered_out(params, key)
    assert !params.has_key?(key), "key #{key.inspect} has not been filtered out"
  end

  #
  # --- Basic interface --------------------------------------------------------
  #

  # --- nothing ----------------------------------------------------------------

  test 'if nothing is permitted, the hash becomes empty' do
    params = ActionController::Parameters.new(:id => '1234')
    permitted = params.permit
    permitted.permitted?
    permitted.empty?
  end

  # --- key --------------------------------------------------------------------

  test 'key: unexpected types are filtered out' do
    params = ActionController::Parameters.new(:id => 1234, :token => 0)
    permitted = params.permit(:id => Numeric, :token => String)
    assert_equal 1234, permitted[:id]
    assert_filtered_out permitted, :token
  end

  test 'key: unknown keys are filtered out' do
    params = ActionController::Parameters.new(:id => '1234', :injected => 'injected')
    permitted = params.permit(:id)
    assert_equal '1234', permitted[:id]
    assert_filtered_out permitted, :injected
  end

  test 'key: arrays are filtered out' do
    [[], [1], ['1']].each do |array|
      params = ActionController::Parameters.new(:id => array)
      permitted = params.permit(:id)
      assert_filtered_out permitted, :id

      %w(i f).each do |suffix|
        params = ActionController::Parameters.new("foo(000#{suffix})" => array)
        permitted = params.permit(:foo)
        assert_filtered_out permitted, "foo(000#{suffix})"
      end
    end
  end

  test 'key: hashes are filtered out' do
    [{}, {:foo => 1}, {:foo => 'bar'}].each do |hash|
      params = ActionController::Parameters.new(:id => hash)
      permitted = params.permit(:id)
      assert_filtered_out permitted, :id

      %w(i f).each do |suffix|
        params = ActionController::Parameters.new("foo(000#{suffix})" => hash)
        permitted = params.permit(:foo)
        assert_filtered_out permitted, "foo(000#{suffix})"
      end
    end
  end

  test 'key: non-permitted scalar values are filtered out' do
    params = ActionController::Parameters.new(:id => Object.new)
    permitted = params.permit(:id)
    assert_filtered_out permitted, :id

    %w(i f).each do |suffix|
      params = ActionController::Parameters.new("foo(000#{suffix})" => Object.new)
      permitted = params.permit(:foo)
      assert_filtered_out permitted, "foo(000#{suffix})"
    end
  end

  test 'key: Boolean matches only true and false' do
    params = ActionController::Parameters.new(:happy => true)
    permitted = params.permit(:happy => Boolean)
    assert_equal true, permitted[:happy]

    params = ActionController::Parameters.new(:happy => false)
    permitted = params.permit(:happy => Boolean)
    assert_equal false, permitted[:happy]

    params = ActionController::Parameters.new(:happy => Object.new)
    permitted = params.permit(:happy => Boolean)
    assert_filtered_out permitted, :happy

  end

  test 'key: it is not assigned if not present in params' do
    params = ActionController::Parameters.new(:name => 'Joe')
    permitted = params.permit(:id)
    assert !permitted.has_key?(:id)
  end

  #
  # --- Nesting ----------------------------------------------------------------
  #

  test "permitted nested parameters" do
    params = ActionController::Parameters.new({
      :book => {
        :title => "Romeo and Juliet",
        :authors => [{
          :name => "William Shakespeare",
          :born => "1564-04-26"
        }, {
          :name => "Christopher Marlowe"
        }, {
          :name => %w(malicious injected names)
        }],
        :details => {
          :pages => 200,
          :genre => "Tragedy"
        }
      },
      :magazine => "Mjallo!"
    })

    permitted = params.permit :book => [ :title, { :authors => [ :name ] }, { :details => {:pages => Numeric} } ]

    assert permitted.permitted?
    assert_equal "Romeo and Juliet", permitted[:book][:title]
    assert_equal "William Shakespeare", permitted[:book][:authors][0][:name]
    assert_equal "Christopher Marlowe", permitted[:book][:authors][1][:name]
    assert_equal 200, permitted[:book][:details][:pages]

    assert_filtered_out permitted[:book][:authors][2], :name

    assert_filtered_out permitted, :magazine
    assert_filtered_out permitted[:book][:details], :genre
    assert_filtered_out permitted[:book][:authors][0], :born
  end

  test "permitted nested parameters with a string or a symbol as a key" do
    params = ActionController::Parameters.new({
      :book => {
        'authors' => [
          { :name => "William Shakespeare", :born => "1564-04-26" },
          { :name => "Christopher Marlowe" }
        ]
      }
    })

    permitted = params.permit :book => [ { 'authors' => [ :name ] } ]

    assert_equal "William Shakespeare", permitted[:book]['authors'][0][:name]
    assert_equal "William Shakespeare", permitted[:book][:authors][0][:name]
    assert_equal "Christopher Marlowe", permitted[:book]['authors'][1][:name]
    assert_equal "Christopher Marlowe", permitted[:book][:authors][1][:name]

    permitted = params.permit :book => [ { :authors => [ :name ] } ]

    assert_equal "William Shakespeare", permitted[:book]['authors'][0][:name]
    assert_equal "William Shakespeare", permitted[:book][:authors][0][:name]
    assert_equal "Christopher Marlowe", permitted[:book]['authors'][1][:name]
    assert_equal "Christopher Marlowe", permitted[:book][:authors][1][:name]
  end

  test "nested arrays with strings" do
    params = ActionController::Parameters.new({
      :book => {
        :genres => ["Tragedy"]
      }
    })

    permitted = params.permit :book => {:genres => [String]}
    assert_equal ["Tragedy"], permitted[:book][:genres]
  end

  test "permit may specify symbols or strings" do
    params = ActionController::Parameters.new({
      :book => {
        :title => "Romeo and Juliet",
        :author => "William Shakespeare"
      },
      :magazine => "Shakespeare Today"
    })

    permitted = params.permit({ :book => ["title", :author] }, "magazine")
    assert_equal "Romeo and Juliet", permitted[:book][:title]
    assert_equal "William Shakespeare", permitted[:book][:author]
    assert_equal "Shakespeare Today", permitted[:magazine]
  end

  test "nested array with strings that should be hashes" do
    params = ActionController::Parameters.new({
      :book => {
        :genres => ["Tragedy"]
      }
    })

    permitted = params.permit :book => { :genres => :type }
    assert permitted[:book][:genres].empty?
  end

  test "nested array with strings that should be hashes and additional values" do
    params = ActionController::Parameters.new({
      :book => {
        :title => "Romeo and Juliet",
        :genres => ["Tragedy"]
      }
    })

    permitted = params.permit :book => [ :title, { :genres => :type } ]
    assert_equal "Romeo and Juliet", permitted[:book][:title]
    assert permitted[:book][:genres].empty?
  end

  test "nested string that should be a hash" do
    params = ActionController::Parameters.new({
      :book => {
        :genre => "Tragedy"
      }
    })

    permitted = params.permit :book => { :genre => :type }
    assert_nil permitted[:book][:genre]
  end

  test "fields_for_style_nested_params" do
    params = ActionController::Parameters.new({
      :book => {
        :authors_attributes => {
          :'0' => { :name => 'William Shakespeare', :age_of_death => '52' },
          :'1' => { :name => 'Unattributed Assistant' },
          :'2' => { :name => %w(injected names)}
        }
      }
    })
    permitted = params.permit :book => { :authors_attributes => [ :name ] }

    assert_not_nil permitted[:book][:authors_attributes]['0']
    assert_not_nil permitted[:book][:authors_attributes]['1']
    assert permitted[:book][:authors_attributes]['2'].empty?
    assert_equal 'William Shakespeare', permitted[:book][:authors_attributes]['0'][:name]
    assert_equal 'Unattributed Assistant', permitted[:book][:authors_attributes]['1'][:name]

    assert_filtered_out permitted[:book][:authors_attributes]['0'], :age_of_death
  end

  test "fields_for_style_nested_params with negative numbers" do
    params = ActionController::Parameters.new({
      :book => {
        :authors_attributes => {
          :'-1' => { :name => 'William Shakespeare', :age_of_death => '52' },
          :'-2' => { :name => 'Unattributed Assistant' }
        }
      }
    })
    permitted = params.permit :book => { :authors_attributes => [:name] }

    assert_not_nil permitted[:book][:authors_attributes]['-1']
    assert_not_nil permitted[:book][:authors_attributes]['-2']
    assert_equal 'William Shakespeare', permitted[:book][:authors_attributes]['-1'][:name]
    assert_equal 'Unattributed Assistant', permitted[:book][:authors_attributes]['-2'][:name]

    assert_filtered_out permitted[:book][:authors_attributes]['-1'], :age_of_death
  end
end
