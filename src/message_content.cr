require "json"
require "base64"

require "./resource"
require "./cache_control"

module Anthropic
  abstract class MessageContent
    include Resource

    abstract def type : String

    property cache_control : CacheControl?

    use_json_discriminator "type", {
      text:        Text,
      image:       Image,
      tool_use:    ToolUse,
      tool_result: ToolResult,
    }

    def no_cache_control! : self
      cache_control! nil
    end

    def cache_control!(@cache_control : CacheControl? = CacheControl.new) : self
      self
    end
  end

  abstract class TextOrImageContent < MessageContent
    def self.new(pull : ::JSON::PullParser)
      raise NotImplementedError.new("Cannot parse Anthropic::TextOrImageContent from JSON")
    end
  end

  class Text < TextOrImageContent
    getter type : String = "text"
    getter text : String

    def initialize(@text, *, @cache_control = nil)
    end

    def to_s(io) : Nil
      if text = @text
        io.puts text
      end
    end
  end

  class Document < TextOrImageContent
    getter type : String = "document"
    getter source : Source

    def self.base64(data : String, cache_control : CacheControl? = nil)
      new(
        data: Base64.strict_encode(data),
        cache_control: cache_control,
      )
    end

    def initialize(*, data : String, @cache_control = nil)
      @source = Source.new(type: :base64, media_type: :pdf, data: data)
    end

    record Source, type : Type, media_type : MediaType, data : String do
      include Resource

      enum Type
        Base64
      end

      enum MediaType
        PDF

        def to_s
          case self
          in .pdf?
            "application/pdf"
          end
        end
      end
    end
  end

  class Image < TextOrImageContent
    getter type : String = "image"
    getter source : Source

    def self.base64(media_type : Source::MediaType, data : String, cache_control : CacheControl? = nil)
      new(
        type: :base64,
        media_type: media_type,
        data: Base64.strict_encode(data),
        cache_control: cache_control,
      )
    end

    def initialize(*, type : Source::Type, media_type : Source::MediaType, data : String, @cache_control = nil)
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

  class ToolUse < MessageContent
    getter type : String = "tool_use"
    getter id : String
    getter name : String
    getter input : Hash(String, JSON::Any::Type)

    def initialize(*, @id, @name, @input)
    end
  end

  class ToolResult < MessageContent
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
