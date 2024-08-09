require "./client"

module Anthropic
  private abstract struct API
    getter client : Client

    def initialize(@client)
    end
  end
end
