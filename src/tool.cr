require "./resource"

module Anthropic
  def self.tools(array : Enumerable)
    array.map { |handler| tool(handler) }
  end

  def self.tools(array : Array(Tool))
    array
  end

  def self.tools(array : Nil)
    [] of Tool(Tool::Handler.class)
  end

  def self.tool(input_type, description : String? = input_type.description, *, name : String = input_type.name) : Tool
    Tool.new(
      name: name,
      description: description,
      input_type: input_type,
    )
  end

  struct Tool(T)
    include Resource

    getter name : String
    getter description : String?
    getter input_type : T

    def initialize(@name, @description, @input_type)
    end

    def to_json(json : JSON::Builder) : Nil
      json.object do
        json.field "name", name
        if description
          json.field "description", description
        end
        json.field "input_schema" do
          input_type.json_schema.to_json json
        end
      end
    end

    abstract struct Handler
      include JSON::Serializable

      def self.description
      end

      def self.parse(json : String)
        raise NotImplementedError.new("Can't parse #{self} from #{json}")
      end

      macro inherited
        def self.parse(json : String)
          from_json json
        end
      end

      abstract def call
    end
  end
end
