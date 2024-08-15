require "json"

module Anthropic
  module Resource
    macro included
      include JSON::Serializable
    end
  end
end
