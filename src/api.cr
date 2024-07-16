require "./client"

module Anthropic
  abstract struct API
    getter client : Client

    def initialize(@client)
    end
  end
end
