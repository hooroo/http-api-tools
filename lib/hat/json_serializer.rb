require "active_support/core_ext/class/attribute"
require "active_support/json"
require 'active_support/core_ext/string/inflections'
require 'hat/relation_includes'
require 'hat/identity_map'

module Hat
  module JsonSerializer

    attr_reader :serializable, :relation_includes, :result, :attribute_mappings, :has_one_mappings, :has_many_mappings, :cached

    def initialize(serializable, options = {})
      @serializable = serializable
      @result = options[:result] || {}
      @relation_includes = options[:relation_includes] || RelationIncludes.new([])
      @identity_map = options[:identity_map] || IdentityMap.new
      @meta_data = { type: root_key.to_s.singularize, root_key: root_key.to_s }
    end

    def to_json(*args)
      JSON.fast_generate(as_json)
    end

    def as_json(*args)

      result[root_key] = []

      Array(serializable).each do |serializable_item|
        serializer_class = serializer_class_for(serializable_item)
        id = serializable_item.id if serializable_item.respond_to? :id
        hashed = { id: id }
        result[root_key] << hashed
        hashed.merge! serializer_class.new(serializable_item, { result: result, identity_map: identity_map }).includes(*relation_includes.includes).to_hash
      end

      add_sideload_data_from_identity_map
      add_meta

      result
    end

    def includes(*includes)
      self.relation_includes.include(includes)
      self
    end

    def meta(data)
      meta_data.merge!(data)
      self
    end

    protected

    attr_accessor :identity_map

    def attributes
      self.class._attributes
    end

    def has_ones
      self.class._relationships[:has_ones]
    end

    def has_manys
      self.class._relationships[:has_manys]
    end

    def to_hash
      hash = attribute_hash.merge({links: has_one_hash.merge(has_many_hash)})
      sideload_has_ones
      sideload_has_manys
      hash
    end

    private

    attr_writer :relation_includes
    attr_accessor :serializer_map, :meta_data

    def add_meta
      result[:meta] = meta_data
    end

    def attribute_hash

      attribute_hash = {}

      attributes.each do |attr_name|
        if self.respond_to? attr_name
          attribute_hash[attr_name] = self.send(attr_name)
        else
          attribute_hash[attr_name] = serializable.send(attr_name)
        end
      end

      attribute_hash

    end

    def has_one_hash

      has_one_hash = {}

      has_ones.each do |attr_name|

        id_attr = "#{attr_name}_id"

        #Use id attr if possible as it's cheaper than referencing the object
        if serializable.respond_to?(id_attr)
          related_id = serializable.send(id_attr)
        else
          related_id = serializable.send(attr_name).try(:id)
        end

        has_one_hash[attr_name] = related_id

      end

      has_one_hash

    end


    def has_many_hash

      has_many_hash = {}

      has_manys.each do |attr_name|
        has_many_relation = serializable.send(attr_name) || []
        has_many_hash[attr_name] = has_many_relation.map(&:id)
      end

      has_many_hash

    end

    def sideload_has_ones

      has_ones.each do |attr_name|

        id_attr = "#{attr_name}_id".to_sym

        if relation_includes.include?(attr_name)
          if related = serializable.send(attr_name)

            type_key = attr_name.to_s.pluralize.to_sym

            unless identity_map.get(type_key, related.id)
              related = serializable.send("#{attr_name}")
              sideload_item(related, attr_name, type_key)
            end
          end
        end
      end
    end

    def sideload_has_manys

      has_manys.each do |attr_name|

        if relation_includes.include?(attr_name)

          has_many_relation = serializable.send("#{attr_name}") || []
          type_key = attr_name

          has_many_relation.each do |related|
            sideload_item(related, attr_name, type_key) unless identity_map.get(type_key, related.id)
          end
        end
      end
    end

    def sideload_item(related, attr_name, type_key)
      serializer_class = serializer_class_for(related)
      includes = relation_includes.nested_includes_for(attr_name) || []
      hashed = serializer_class.new(related, { result: result, identity_map: identity_map }).includes(*includes).to_hash

      identity_map.put(type_key, related.id, hashed)
    end

    def add_sideload_data_from_identity_map
      linked = result[:linked] = {}
      identity_map.to_hash.each do |key, type_map|
        linked[key] = type_map.values
      end
    end

    def serializer_class_for(model)
      "#{model.class.name}Serializer".constantize
    end

    def is_active_record_relation?(relation)
      #This is a pretty terrible way to test for this. find a better way
      serializable.respond_to? :klass
    end

    def root_key
      @_root_key ||= self.class.name.split("::").last.underscore.gsub('_serializer', '').pluralize.to_sym
    end

    #----Module Inclusion

    def self.included(base)

      base.class_attribute :_attributes
      base.class_attribute :_relationships

      base._attributes = []
      base._relationships = { has_ones: [], has_manys: [] }

      base.extend(ClassMethods)

    end

    module ClassMethods
      def attributes(*args)
        self._attributes = args
      end

      def has_one(has_one)
        self._relationships[:has_ones] << has_one
      end

      def has_many(has_many)
        self._relationships[:has_manys] << has_many
      end
    end

  end
end


