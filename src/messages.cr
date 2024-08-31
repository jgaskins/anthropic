require "./api"
require "./generated_message"
require "./event_source"

module Anthropic
  struct Messages < API
    CREATE_HEADERS = HTTP::Headers{
      "anthropic-beta" => {
        # Not sure if this one is still necessary because tools seem to work
        # without it, but keeping it here until I see something official.
        "tools-2024-04-04",

        # 3.5 Sonnet only supports 4k tokens by default, but you can opt into
        # up to 8k output tokens.
        # https://x.com/alexalbert__/status/1812921642143900036
        "max-tokens-3-5-sonnet-2024-07-15",

        # https://www.anthropic.com/news/prompt-caching
        "prompt-caching-2024-07-31",
      }.join(','),
    }

    def create(
      *,
      model : String,
      max_tokens : Int32,
      messages : Array(Anthropic::Message),
      system : String | Anthropic::MessageContent | Array | Nil = nil,
      temperature : Float64? = nil,
      top_k : Int64? = nil,
      top_p : Float64? = nil,
      tools : Array? = nil,
      run_tools : Bool = true,
    ) : GeneratedMessage
      tools = Anthropic.tools(tools)
      system = MessageContentTransformer.new.call system

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

      # TODO: Investigate whether the `beta=tools` is needed since we're using
      # the tools beta header above.
      response = client.post "/v1/messages?beta=tools",
        headers: CREATE_HEADERS,
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

    # Send your prompt to the API and yield `Event`s as they are fed back in.
    @[Experimental("Streaming message events kinda/sorta works, but needs further testing")]
    def create(
      *,
      model : String,
      max_tokens : Int32,
      messages : Array(Anthropic::Message),
      system : String? = nil,
      temperature : Float64? = nil,
      top_k : Int64? = nil,
      top_p : Float64? = nil,
      # Tools are not supported yet for the block form of the method.
      # tools : Array(Tool)? = client.tools.values,
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
      getter system : String | MessageContent | Array(MessageContent) | Nil
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

    struct MessageContentTransformer
      def call(contents : Array) : Array(MessageContent)
        contents.flat_map { |content| call(content).as(MessageContent) }
      end

      def call(contents : Array(MessageContent)) : Array(MessageContent)
        contents.map(&.as(MessageContent))
      end

      def call(content : MessageContent) : Array(MessageContent)
        [content.as(MessageContent)]
      end

      def call(string : String) : Array(MessageContent)
        call Text.new(string).as(MessageContent)
      end

      def call(nothing : Nil) : Nil
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

  private module Converters
    module TimeSpan
      extend self

      def to_json(value : Time::Span, json : JSON::Builder)
        json.number value.total_seconds
      end
    end
  end
end
