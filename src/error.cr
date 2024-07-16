module Anthropic
  class Error < ::Exception
    def self.from_response_body(body : String)
      response = Response.from_json(body)
      TYPE_MAP[response.error.type].new(response.error.message)
    end

    def initialize(message : String)
      super message
    end

    private TYPE_MAP = {
      # 400 - invalid_request_error: There was an issue with the format or content of your request. We may also use this error type for other 4XX status codes not listed below.
      "invalid_request_error" => InvalidRequestError,

      # 401 - authentication_error: There's an issue with your API key.
      "authentication_error" => AuthenticationError,

      # 403 - permission_error: Your API key does not have permission to use the specified resource.
      "permission_error" => PermissionError,

      # 404 - not_found_error: The requested resource was not found.
      "not_found_error" => NotFoundError,

      # 429 - rate_limit_error: Your account has hit a rate limit.
      "rate_limit_error" => RateLimitError,

      # 500 - api_error: An unexpected error has occurred internal to Anthropic's systems.
      "api_error" => APIError,

      # 529 - overloaded_error: Anthropic's API is temporarily overloaded.
      "overloaded_error" => OverloadedError,
    }

    class InvalidRequestError < self
    end

    class AuthenticationError < self
    end

    class PermissionError < self
    end

    class NotFoundError < self
    end

    class RateLimitError < self
    end

    class APIError < self
    end

    class OverloadedError < self
    end

    struct Response
      include Resource

      getter type : String
      getter error : Error

      struct Error
        include Resource

        getter type : String
        getter message : String
      end
    end
  end
end
