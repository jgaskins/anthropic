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
      tools : Array(Tool) | Array(Tool::Handler.class) | Nil = client.tools.values,
      run_tools : Bool = true,
    ) : GeneratedMessage
      if tools.is_a? Array(Tool::Handler.class)
        tools = Anthropic.tools(tools)
      end

      request = Request.new(
        model: model,
        max_tokens: max_tokens,
        system: system,
        messages: messages,
        temperature: temperature,
        top_k: top_k,
        top_p: top_p,
        tools: tools,
      )

      response = client.post "/v1/messages?beta=tools",
        headers: HTTP::Headers{"anthropic-beta" => "tools-2024-05-16"},
        body: request,
        as: GeneratedMessage

      if run_tools && response.stop_reason.try(&.tool_use?)
        tool_uses = response.content.compact_map(&.as?(ToolUse))
        tools = tool_uses.compact_map { |tool_use| tools.find { |t| t.name == tool_use.name } }
        tool_handlers = tools.map_with_index { |tool, index| tool.input_type.parse(tool_uses[index].input.to_json) }

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
      getter tools : Array(Tool)?
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
