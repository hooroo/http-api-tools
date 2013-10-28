require "active_support/core_ext/class/attribute"
require "hat/model/type_coercions"

#Mix in to PORO to get basic attribute definition with type coercion and defaults.
#class MyClass
#  attribute :name
#  attribute :date, type: :date_time
#  attribute :tags, default: []
#
#NOTE: Be careful of adding default values other than primitives, arrays or basic hashes. Anything more
#Complex will need to be copied into each object rather than by direct reference - see the way
#arrays and hashes are handled in the 'default_for' method below.
module Hat
  module Model
    module Attributes

      include TypeCoercions

      def initialize(attrs = {})
        attrs = attrs.with_indifferent_access
        attributes.each do |attr_name, options|
          value = attrs[attr_name] || default_for(options)
          if coercion_type = options[:type]
            value = self.send("to_#{coercion_type}", value)
          end
          self.send("#{attr_name}=", value)
        end
        self.errors = attrs[:errors] || {}
      end

      def attributes
        self.class._attributes
      end

      #make sure we don't pass references to the same default object to each instance. Copy/dup where appropriate
      def default_for(options)
        assert_default_type_valid(options)
        default = options[:default]
        if default.kind_of? Array
          [].concat(default)
        elsif default.kind_of? Hash
          default.dup
        end
      end

      def assert_default_type_valid(options)
        if options[:default]
          default_class = options[:default].class
          unless [Array, Hash, Integer, Float, String].include? default_class
            raise "Default values of type #{default_class.name} are not supported."
          end
        end
      end

      #----Module Inclusion

      def self.included(base)
        base.class_attribute :_attributes
        base._attributes = {}
        base.extend(ClassMethods)
        base.send(:attr_accessor, :errors)
      end

      module ClassMethods

        def attribute(name, options = {})
          self._attributes[name] = options
          self.send(:attr_accessor, name.to_sym)
        end

      end

    end
  end
end