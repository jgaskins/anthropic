require "./api"
require "./generated_message"
require "./event_source"

module Anthropic
  struct Messages < API
    def create(
      *,
      model : String,
      max_tokens : Int32,
      messages : Array(Message),
      system : String? = nil,
      temperature : Float64? = nil,
      top_k : Int64? = nil,
      top_p : Float64? = nil,
      tools : Array? = nil,
      run_tools : Bool = true,
    ) : GeneratedMessage
      tools = Anthropic.tools(tools)

      request = Request.new(
        model: model,
        max_tokens: max_tokens,
        system: system,
        messages: messages,
        temperature: temperature,
        top_k: top_k,
        top_p: top_p,
        tools: tools.to_json,
      )

      headers = HTTP::Headers.new

      # Tools are apparently in beta as of this writing.
      if tools.try(&.any?)
        headers.add "anthropic-beta", "tools-2024-05-16"
      end

      # 3.5 Sonnet only supports 4k tokens by default, but you can opt into
      # up to 8k output tokens.
      # https://x.com/alexalbert__/status/1812921642143900036
      if model.includes?("3-5-sonnet") && max_tokens > 4096
        headers.add "anthropic-beta", "max-tokens-3-5-sonnet-2024-07-15"
      end

      # TODO: Investigate whether the `beta=tools` is needed since we're using
      # the tools beta header above.
      response = client.post "/v1/messages?beta=tools",
        headers: headers,
        body: request,
        as: GeneratedMessage
      response.message_thread = messages.dup << response.to_message

      if run_tools && response.stop_reason.try(&.tool_use?)
        tool_uses = response.content.compact_map(&.as?(ToolUse))
        tools_used = tool_uses.compact_map { |tool_use| tools.find { |t| t.name == tool_use.name } }
        tool_handlers = tools_used.map_with_index { |tool, index| tool.input_type.parse(tool_uses[index].input.to_json) }

        if tool_handlers.any?
          result_texts = tool_handlers.map do |tool_handler|
            Text.new(tool_handler.call.to_json).as(Text)
          end
          create(
            model: model,
            max_tokens: max_tokens,
            messages: messages + [
              response.to_message,
              Message.new(
                content: result_texts.map_with_index do |result_text, index|
                  ToolResult.new(
                    tool_use_id: tool_uses[index].id.not_nil!,
                    content: [result_text],
                  ).as(MessageContent)
                end,
              ),
            ],
            system: system,
            temperature: temperature,
            top_k: top_k,
            top_p: top_p,
            tools: tools,
            run_tools: run_tools,
          )
        else
          response
        end
      else
        response
      end
    end

    def create(
      *,
      model : String,
      max_tokens : Int32,
      messages : Array(Anthropic::Message),
      system : String? = nil,
      temperature : Float64? = nil,
      top_k : Int64? = nil,
      top_p : Float64? = nil,
      tools : Array(Tool)? = client.tools.values,
      &block : Event -> T
    ) forall T
      client.http do |http|
        headers = HTTP::Headers{
          "anthropic-beta" => "tools-2024-04-04",
          "Accept"         => "text/event-stream",
        }
        body = Request.new(
          model: model,
          max_tokens: max_tokens,
          system: system,
          messages: messages,
          temperature: temperature,
          top_k: top_k,
          top_p: top_p,
          tools: tools,
          stream: true,
        ).to_json
        http.post "/v1/messages?beta=tools", headers: headers, body: body do |response|
          EventSource.new(response)
            .on_message do |message, es|
              message.data.each do |data|
                block.call Event::TYPE_MAP[message.event].from_json(data)
              end
            end
            .run
          response
        end
      end
    end

    struct Request
      include Resource

      getter model : String
      getter messages : Array(Message)
      getter max_tokens : Int32
      getter system : String?
      getter metadata : Hash(String, String)?
      getter stop_sequences : Array(String)?
      getter? stream : Bool?
      getter temperature : Float64?
      @[JSON::Field(converter: String::RawConverter)]
      getter tools : String?
      getter top_k : Int64?
      getter top_p : Float64?
      getter extra_headers : HTTP::Headers?
      getter extra_query : Query?
      getter extra_body : Body?

      # @[JSON::Field(converter: ::Anthropic::Converters::TimeSpan)]
      # field timeout : Time::Span?

      def initialize(
        *,
        @model,
        @max_tokens,
        @messages,
        @system = nil,
        @metadata = nil,
        @stop_sequences = nil,
        @stream = nil,
        @temperature = nil,
        @tools = nil,
        @top_k = nil,
        @top_p = nil,
        @extra_headers = nil,
        @extra_query = nil,
        @extra_body = nil
        # @timeout = nil
      )
      end
    end

    struct Query
      include Resource
    end

    struct Body
      include Resource
    end
  end

  class Client
    def messages
      Messages.new self
    end
  end

  module Converters
    module TimeSpan
      extend self

      def to_json(value : Time::Span, json : JSON::Builder)
        json.number value.total_seconds
      end
    end
  end
end
