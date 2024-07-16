require "./resource"
require "json"
require "base64"

module Anthropic
  abstract struct MessageContent
    include Resource

    abstract def type : String

    use_json_discriminator "type", {
      text:        Text,
      image:       Image,
      tool_use:    ToolUse,
      tool_result: ToolResult,
    }
  end

  abstract struct TextOrImageContent < MessageContent
    def self.new(pull : ::JSON::PullParser)
      raise "oops"
    end
  end

  struct Text < TextOrImageContent
    getter type : String = "text"
    getter text : String

    def initialize(@text)
    end

    def to_s(io) : Nil
      if text = @text
        io.puts text
      end
    end
  end

  struct Image < TextOrImageContent
    getter type : String = "image"
    getter source : Source

    def self.base64(media_type : Source::MediaType, data : String)
      new(
        type: :base64,
        media_type: media_type,
        data: Base64.strict_encode(data),
      )
    end

    def initialize(*, type : Source::Type, media_type : Source::MediaType, data : String)
      @source = Source.new(type: type, media_type: media_type, data: data)
    end

    record Source, type : Type, media_type : MediaType, data : String do
      include Resource

      enum Type
        Base64
      end

      enum MediaType
        JPEG
        PNG
        GIF
        WEBP

        def to_s
          "image/#{super.downcase}"
        end
      end
    end
  end

  struct ToolUse < MessageContent
    getter type : String = "tool_use"
    getter id : String
    getter name : String
    getter input : Hash(String, JSON::Any::Type)

    def initialize(*, @id, @name, @input)
    end
  end

  struct ToolResult < MessageContent
    getter type : String = "tool_result"
    getter tool_use_id : String
    @[JSON::Field(key: "is_error")]
    getter? error : Bool = false
    getter content : Array(Text | Image)

    def self.new(*, tool_use_id : String, error : Bool = false, content : Array(Text) | Array(Image))
      new(
        tool_use_id: tool_use_id,
        error: error,
        content: content.map &.as(Text | Image),
      )
    end

    def initialize(*, @tool_use_id, @error = false, @content)
    end
  end
end
