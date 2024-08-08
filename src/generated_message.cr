require "./resource"
require "json"

require "./message"

struct Anthropic::GeneratedMessage
  include Resource

  # Unique object identifier.
  #
  # The format and length of IDs may change over time.
  getter id : String
  # This is an array of content blocks, each of which has a `type` that determines
  # its shape. Currently, the only `type` in responses is `"text"`.
  #
  # Example:
  #
  # ```json
  # [{ "type": "text", "text": "Hi, I'm Claude." }]
  # ```
  #
  # If the request input `messages` ended with an `assistant` turn, then the
  # response `content` will continue directly from that last turn. You can use this
  # to constrain the model's output.
  #
  # For example, if the input `messages` were:
  #
  # ```json
  # [
  #   {
  #     "role": "user",
  #     "content": "What's the Greek name for Sun? (A) Sol (B) Helios (C) Sun"
  #   },
  #   { "role": "assistant", "content": "The best answer is (" }
  # ]
  # ```
  #
  # Then the response `content` might be:
  #
  # ```json
  # [{ "type": "text", "text": "B)" }]
  # ```
  getter content : Array(MessageContent) { [] of MessageContent }

  # Object type — for `Message`s, this is always `"message"`.
  getter type : String

  # Conversational role of the generated message. This will always be `:assistant`.
  getter role : Message::Role

  # The model that handled the request.
  getter model : String

  # Which custom stop sequence was generated, if any. This value will be a non-
  # `nil` string if one of your custom stop sequences was generated.
  getter stop_sequence : String?

  # Messages that were passed to the
  getter message_thread : Array(Message) { [to_message] }

  protected setter message_thread

  # Billing and rate-limit usage.
  #
  # Anthropic's API bills and rate-limits by token counts, as tokens represent the
  # underlying cost to our systems.
  #
  # Under the hood, the API transforms requests into a format suitable for the
  # model. The model's output then goes through a parsing stage before becoming an
  # API response. As a result, the token counts in `usage` will not match one-to-one
  # with the exact visible content of an API request or response.
  #
  # For example, `output_tokens` will be non-zero, even for an empty string response
  # from Claude.
  getter usage : Usage

  # The reason that we stopped. This may be one the following values:
  #
  # - `:end_turn`: the model reached a natural stopping point
  # - `:max_tokens`: we exceeded the requested `max_tokens` or the model's maximum
  # - `:stop_sequence`: one of your provided custom `stop_sequences` was generated
  #
  # In non-streaming mode this value is always non-null. In streaming mode, it is
  # `nil` in the `MessageStart` event and non-`nil` otherwise.
  getter stop_reason : StopReason?

  def to_message
    Message.new(
      role: role,
      content: content,
    )
  end

  def to_s(io) : Nil
    content.each do |item|
      io.puts item
    end
  end

  abstract struct Content
    include Resource

    getter type : Type

    use_json_discriminator "type", {
      text:     Text,
      tool_use: ToolUse,
    }

    enum Type
      Text
      ToolUse
    end
  end

  struct Text < Content
    getter text : String?

    def to_s(io) : Nil
      if text = @text
        io.puts text
      end
    end
  end

  struct ToolUse < Content
    getter id : String?
    getter name : String?
    @[JSON::Field(converter: ::Anthropic::GeneratedMessage::ToolUse::PossibleSchema)]
    getter input : JSON::Any

    module PossibleSchema
      def self.from_json(json : JSON::PullParser) : JSON::Any
        hash = Hash(String, JSON::Any).new(json)
        result = hash.fetch("properties") { JSON::Any.new(nil) }

        if result.as_h?
          result
        else
          JSON::Any.new(hash)
        end
      end
    end

    struct Schema
      include JSON::Serializable
      include JSON::Serializable::Unmapped

      getter properties : JSON::Any
    end
  end

  struct Usage
    include Resource

    getter input_tokens : Int64
    getter output_tokens : Int64
  end

  enum StopReason
    EndTurn
    MaxTokens
    StopSequence
    ToolUse
  end
end
