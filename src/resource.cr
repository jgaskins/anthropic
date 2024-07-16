require "json"

module Anthropic
  module Resource
    macro included
      include JSON::Serializable
    end

    # macro field(var, key = nil, &block)
    #   @[JSON::Field(key: {{key ? key : var.var.stringify}})]
    #   # @[MessagePack::Field(key: {{key ? key : var.var.camelcase(lower: true).stringify}})]
    #   getter {{var}} {{block}}
    # end

    # macro field?(var, key = nil, &block)
    #   @[JSON::Field(key: {{key ? key : var.var.stringify}})]
    #   # @[MessagePack::Field(key: {{key ? key : var.var.camelcase(lower: true).stringify}})]
    #   getter? {{var}} {{block}}
    # end
  end
end
