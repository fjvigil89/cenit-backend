module Mongoff
  module MetadataAccess

    SIMPLE_TYPES = %w(integer number boolean string).freeze

    def property_for(name)
      @properties_by_name ||= {}
      unless @properties_by_name.key?(name)
        segment_property = nil
        name_property = nil
        if (edi_opts = schema['edi']) && (segments = edi_opts['segments'])
          segment_property = segments[name]
          name_property = name if property?(name)
        else
          properties.each do |property|
            next if segment_property
            schema = property_model(property).schema
            if (edi_opts = schema['edi']) && edi_opts['segment'] == name
              segment_property = property
            else
              schema = property_schema(property)
              segment_property = property if ((edi_opts = schema['edi']) && edi_opts['segment'] == name)
            end
            name_property = property if property == name
          end
        end
        @properties_by_name[name] = segment_property || name_property
      end
      @properties_by_name[name]
    end

    def properties_schemas
      @properties_schemas ||= ((schema = self.schema).is_a?(Hash) && schema['type'] == 'object' && schema['properties']) || {}
    end

    def model_properties_schemas
      properties_schemas.select { |_, schema| (%w(integer number boolean string) + [nil]).exclude?(schema['type']) }
    end

    def simple_properties_schemas(simple_types = SIMPLE_TYPES)
      properties_schemas.select { |_, schema| simple_types.include?(schema['type']) }
    end

    def index_ignore_properties
      []
    end

    def unique_properties
      unless @unique_properties
        @unique_properties = []
        properties.each do |property|
          sch = property_schema(property)
          next if sch['referenced']
          @unique_properties << property if sch['unique']
          if sch['type'] == 'object' && (embedded_properties = sch['properties']).is_a?(Hash)
            embedded_properties.each do |embedded_property, embedded_schema|
              next if embedded_property == '_id'
              @unique_properties << "#{property}.#{embedded_property}" if embedded_schema.is_a?(Hash) && embedded_schema['unique']
            end
          end
        end
      end
      @unique_properties.dup
    end

    def property_schema(property)
      @merged_properties_schemas ||= {}
      property = property.to_s
      @merged_properties_schemas[property] ||
        ((sch = properties_schemas[property]) &&
          (@merged_properties_schemas[property] = data_type.merge_schema(sch)))
    end

    def properties
      properties_schemas.keys
    end

    def property?(property)
      properties_schemas.key?(property.to_s)
    end

    def requires?(property)
      (require = schema['required']) && require.include?(property.to_s)
    end

    MONGO_TYPE_MAP = {
      integer: Integer,
      number: Float,
      boolean: Mongoid::Boolean,
      string: {
        default: String,
        format: {
          date: Date,
          'date-time': DateTime,
          time: Time
        }
      },
      object: Hash,
      array: Array,
      nil => NilClass
    }.with_indifferent_access

    def mongo_type_for(field, schema, property_model = nil)
      property_model ||= property_model(field) if field
      schema ||= property_schema(field)
      if property_model && schema['referenced']
        property_model.mongo_type_for(:_id, nil) #TODO Set schema parameter default to nil
      elsif schema
        if (key = schema['type']).nil? && (one_of = schema['oneOf']).is_a?(Array)
          one_of.collect { |sch| mongo_type_for(nil, sch) }.flatten.uniq
        else
          if key.is_a?(Array)
            return key.map { |type| mongo_type_for(nil, { 'type' => type }) }.flatten.uniq
          elsif key.nil? && (%w(id _id).include?((str = field.to_s)) || str.end_with?('_id'))
            type = BSON::ObjectId
          elsif (type = MONGO_TYPE_MAP[key] || NilClass).is_a?(Hash)
            type = type['format'][schema['format']] || type['default']
          end
          [type]
        end
      elsif %w(id _id).include?((str = field.to_s)) || str.end_with?('_id')
        [BSON::ObjectId]
      else
        [NilClass]
      end
    end

    def type_symbol_for(schema)
      mongo_type_for(nil, schema).collect(&:to_s).collect(&:downcase).collect(&:to_sym)
    end

    def search_properties
      properties.select do |prop|
        prop != '_type' &&
          (schema = property_schema(prop)) &&
          schema['type'] == 'string' &&
          schema['format'] != 'date' &&
          schema['format'] != 'date-time' &&
          schema['format'] != 'time' &&
          schema['format'] != 'symbol'
      end
    end

    def search(query)
      where(search_selector(query))
    end

    def search_selector(query)
      if query.empty?
        return {}
      end

      hierarchy =
        if self.is_a?(Class) && self < ::Setup::ClassHierarchyAware
          concrete_class_hierarchy
        else
          [self]
        end

      selectors = hierarchy.map do |model|
        conditions = model.search_properties_selector(query)
        if hierarchy.length > 1
          conditions = { '$and' => [
            { '_type' => model.name },
            conditions
          ] }
        end
        conditions
      end

      if selectors.length > 1
        { '$or' => selectors }
      else
        selectors[0]
      end
    end

    def search_properties_selector(query)
      {
        '$or' => search_properties.map do |prop|
          { prop => { '$regex' => "(?i)#{query}" } }
        end
      }
    end
  end
end