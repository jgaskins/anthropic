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
  getter tools : Hash(String, Tool) = {} of String => Tool

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

  # Add a tool to the list of available tools that this client can use.
  def add_tool(input_type : Tool::Handler.class, description : String? = input_type.description, *, name : String = input_type.name) : self
    if tools.has_key? name
      raise ArgumentError.new("Duplicate tool name declared")
    end

    tools[name] = tool(input_type, description, name: name)
    self
  end

#   def tool_handlers_for(response : GeneratedMessage) : Array
#     if response.stop_reason.try(&.tool_use?) && (tool_uses = response.content.compact_map(&.as?(GeneratedMessage::ToolUse))) && (tools = tool_uses.map { |tool_use| self.tools[tool_use.name]? })
#       tools.map_with_index do |tool, index|
#         tool.input_type.parse(tool_uses[index].input.to_json)
#       end
#     else
#       [] of String
#     end
#   end

#   def tool_handlers_for(event : ContentBlockStart::ContentBlock) : Array
#     if event.type.try(&.tool_use?) && (name = event.name) && (tool = tools[name]?)
#       [tool.input_type.parse(event.input.to_json)]
#     else
#       [] of String
#     end
#   end

#   def tool_handlers_for(nothing : Nil) : Array
#     [] of String
#   end

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
