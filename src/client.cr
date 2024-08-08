require "db/pool"
require "http/client"
require "json"
require "json-schema"
require "log"

require "./tool"
require "./error"

class Anthropic::Client
  getter api_key : String
  getter base_uri : URI

  def initialize(
    @api_key = ENV["ANTHROPIC_API_KEY"],
    @base_uri = URI.parse(ENV.fetch("ANTHROPIC_BASE_URL", "https://api.anthropic.com")),
    @log = Log.for(self.class)
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

  protected def post(path : String, body, *, headers : HTTP::Headers? = nil, as type : T.class = JSON::Any) forall T
    response = http &.post path, headers: headers, body: body.to_json
    if response.success?
      T.from_json response.body
    else
      raise Error.from_response_body(response.body)
    end
  end

  protected def http
    @pool.checkout { |http| yield http }
  end
end
