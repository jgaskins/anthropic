require "db/pool"
require "http/client"
require "json"
require "json-schema"
require "log"

require "./tool"
require "./error"

# The `Anthropic::Client` is the entrypoint for using the Anthropic API in
# Crystal.
#
# ```
# claude = Anthropic::Client.new # get API key from the ENV
# puts claude.messages.create(
#   model: Anthropic.model_name(:haiku),
#   messages: [Anthropic::Message.new("Write a haiku about the Crystal programming language")],
#   max_tokens: 4096,
# )
# # Sparkling Crystal code,
# # Elegant and swift syntax,
# # Shines with precision.
# ```
#
# The client is concurrency-safe, so you don't need to wrap requests in a mutex
# or manage a connection pool yourself.
class Anthropic::Client
  getter api_key : String
  getter base_uri : URI

  # Instantiate a new client with the API key provided either directly or via
  # the `ANTHROPIC_API_KEY` environment variable. You can optionally provide a
  # base URI to connect to if you are using a different but compatible API
  # provider.
  def initialize(
    @api_key = ENV["ANTHROPIC_API_KEY"],
    @base_uri = URI.parse(ENV.fetch("ANTHROPIC_BASE_URL", "https://api.anthropic.com")),
    @log = Log.for(self.class),
  )
    options = {
      max_idle_pool_size: 10,
    }
    @pool = DB::Pool(HTTP::Client).new(DB::Pool::Options.new(**options)) do
      http = HTTP::Client.new(@base_uri)
      http.before_request do |request|
        request.headers["X-API-Key"] = @api_key
        request.headers["Content-Type"] ||= "application/json"
        request.headers["User-Agent"] = "Anthropic Crystal Client (https://github.com/jgaskins/anthropic)"
        request.headers["Anthropic-Version"] = "2023-06-01"
      end
      http
    end
  end

  def models
    http &.get "/v1/models" do |response|
      if response.success?
        ModelsResponse.from_json(response.body_io).data
      else
        raise Error.new("Unexpected HTTP response status: #{response.status} - #{response.body_io.gets_to_end}")
      end
    end
  end

  private struct ModelsResponse
    include Resource

    getter data : Array(Model)
  end

  struct Model
    include Resource

    getter id : String
    getter display_name : String
    getter created_at : Time
  end

  protected def post(path : String, body, *, headers : HTTP::Headers? = nil, retries = 3, as type : T.class = JSON::Any) forall T
    response = http &.post path, headers: headers, body: body.to_json
    case response.status
    when .success?
      T.from_json response.body
    when .overloaded?
      if retries >= 0
        sleep 1.second
        post(path, body, headers: headers, retries: retries - 1, as: T)
      else
        raise Error.from_response_body(response.body)
      end
    else
      raise Error.from_response_body(response.body)
    end
  end

  protected def http(&)
    @pool.checkout { |http| yield http }
  end
end

enum HTTP::Status
  def overloaded?
    value == 529
  end
end
