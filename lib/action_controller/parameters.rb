require 'date'
require 'bigdecimal'
require 'stringio'

require 'active_support/concern'
require 'active_support/core_ext/hash/indifferent_access'
require 'action_controller'
require 'action_dispatch/http/upload'

module ActionController
  class ParameterMissing < IndexError
    attr_reader :param

    def initialize(param)
      @param = param
      super("key not found: #{param}")
    end
  end

  class UnpermittedParameters < IndexError
    attr_reader :params

    def initialize(params)
      @params = params
      super("found unpermitted parameters: #{params.join(", ")}")
    end
  end

  class Parameters < ActiveSupport::HashWithIndifferentAccess
    attr_accessor :permitted
    alias :permitted? :permitted
    attr_accessor :klass

    cattr_accessor :action_on_unpermitted_parameters, :instance_accessor => false

    # Never raise an UnpermittedParameters exception because of these params
    # are present. They are added by Rails and it's of no concern.
    NEVER_UNPERMITTED_PARAMS = %w( controller action )

    def initialize(attributes = nil, klass = String)
      super(attributes)
      @permitted = false
      @klass = klass
    end

    def permit!
      each_pair do |key, value|
        convert_hashes_to_parameters(key, value)
        self[key].permit! if self[key].respond_to? :permit!
      end

      @permitted = true
      self
    end

    def require(key)
      self[key].presence || raise(ActionController::ParameterMissing.new(key))
    end

    alias :required :require

    def permit(*filters)
      params = self.class.new
      filters.each do |filter|
        rule = filter.is_a?(Hash) ? filter : default_rule(filter)
        if rule.values.one? && rule.values.first.is_a?(Class)
          permitted_scalar_filter(params, rule.keys.first, rule.values.first)
        else
          apply_filter(params, rule)
        end
      end

      unpermitted_parameters!(params) if self.class.action_on_unpermitted_parameters

      params.permit!
    end

    def [](key)
      convert_hashes_to_parameters(key, super)
    end

    def fetch(key, *args)
      convert_hashes_to_parameters(key, super)
    rescue KeyError, IndexError
      raise ActionController::ParameterMissing.new(key)
    end

    def slice(*keys)
      self.class.new(super).tap do |new_instance|
        new_instance.instance_variable_set :@permitted, @permitted
      end
    end

    def dup
      self.class.new(self).tap do |duplicate|
        duplicate.default = default
        duplicate.instance_variable_set :@permitted, @permitted
      end
    end

    protected
      def convert_value(value)
        if value.class == Hash
          self.class.new_from_hash_copying_default(value)
        elsif value.is_a?(Array)
          value.dup.replace(value.map { |e| convert_value(e) })
        else
          value
        end
      end

    private

      def convert_hashes_to_parameters(key, value)
        if value.is_a?(Parameters) || !value.is_a?(Hash)
          value
        else
          # Convert to Parameters on first access
          self[key] = self.class.new(value)
        end
      end

      def permitted_scalar?(value, klass)
        value.is_a?(klass)
      end

      def array_of_permitted_scalars?(value,klass)
        if value.is_a?(Array)
          value.all? {|element| permitted_scalar?(element,klass)}
        end
      end

      def permitted_scalar_filter(params, key, klass)
        if has_key?(key) && permitted_scalar?(self[key],klass)
          params[key] = self[key]
        end

        keys.grep(/\A#{Regexp.escape(key.to_s)}\(\d+[if]?\)\z/).each do |key|
          if permitted_scalar?(self[key],klass)
            params[key] = self[key]
          end
        end
      end

      def array_of_permitted_scalars_filter(params, key, rule)
        raise ArgumentError unless rule.one?
        if has_key?(key) && array_of_permitted_scalars?(self[key],rule.first)
          params[key] = self[key]
        end
      end

      def apply_filter(params, filter)
        filter = filter.with_indifferent_access

        # Slicing filters out non-declared keys.
        slice(*filter.keys).each do |key, value|

          rule = filter[key]

          # Declaration {:favorite_numbers => [Numeric]}
          if rule.is_a?(Array) && rule.first.is_a?(Class)
            array_of_permitted_scalars_filter(params, key, rule)
          # Declaration {:favorite_number => Numeric} or :uuid [=> String]
          elsif rule.is_a?(Class)
            permitted_scalar_filter(params, key, rule)
          else
            # Declaration {:user => :name} or {:user => [:name, :age, {:address => ...}]}
            raise ArgumentError if rule.empty?
            params[key] = each_element(value) do |element|
              if element.is_a?(Hash)
                element = self.class.new(element) unless element.respond_to?(:permit)
                element.klass = key.camelize.constantize rescue String
                element.permit(*Array.wrap(rule))
              end
            end
          end
        end
      end

      def default_rule(filter)
        if @klass.respond_to?(:columns) && (type = @klass.columns.find { |attr| attr.name == filter.to_s })
          {filter => type.klass}
        else
          {filter => String}
        end
      end

      def each_element(value)
        if value.is_a?(Array)
          value.map { |el| yield el }.compact
          # fields_for on an array of records uses numeric hash keys.
        elsif value.is_a?(Hash) && value.keys.all? { |k| k =~ /\A-?\d+\z/ }
          hash = value.class.new
          value.each { |k,v| hash[k] = yield v }
          hash
        else
          yield value
        end
      end

      def unpermitted_parameters!(params)
        return unless self.class.action_on_unpermitted_parameters

        unpermitted_keys = unpermitted_keys(params)

        if unpermitted_keys.any?
          case self.class.action_on_unpermitted_parameters
          when :log
            ActionController::Base.logger.debug "Unpermitted parameters: #{unpermitted_keys.join(", ")}"
          when :raise
            raise ActionController::UnpermittedParameters.new(unpermitted_keys)
          end
        end
      end

      def unpermitted_keys(params)
        self.keys - params.keys - NEVER_UNPERMITTED_PARAMS
      end
  end

  module StrongParameters
    extend ActiveSupport::Concern

    included do
      rescue_from(ActionController::ParameterMissing) do |parameter_missing_exception|
        render :text => "Required parameter missing: #{parameter_missing_exception.param}", :status => :bad_request
      end
    end

    def params
      @_params ||= Parameters.new(request.parameters)
    end

    def params=(val)
      @_params = val.is_a?(Hash) ? Parameters.new(val) : val
    end
  end
end

ActionController::Base.send :include, ActionController::StrongParameters
