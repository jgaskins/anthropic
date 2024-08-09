require "http/client/response"

require "./resource"
require "./generated_message"

module Anthropic
  class EventSource
    getter response : HTTP::Client::Response
    getter last_id : String? = nil

    def initialize(@response, @last_id = nil)
    end

    def on_message(&@on_message : EventMessage, self ->) : self
      self
    end

    def on_error(&@on_error : NamedTuple(status_code: Int32, message: String) ->) : self
      self
    end

    def stop : Nil
      @abort = true
    end

    def run : Nil
      lines = [] of String
      io = response.body_io
      last_message = nil

      loop do
        break if @abort
        break unless line = io.gets

        if line.empty? && !lines.empty?
          last_message = parse_event_message(lines)
          last_message.id.try { |id| @last_id = id }
          @on_message.try &.call(last_message, self)
          lines.clear
        else
          lines << line
        end
      end

      if last_message
        if last_message.id.try(&.empty?) && @abort
          last_message.retry.try do |retry_after|
            sleep retry_after / 1000
          end
        end
      end
    end

    private def parse_event_message(lines : Array(String)) : EventMessage
      id, event, retry = nil, nil, nil
      data = Array(String).new

      lines.each_with_index do |line, i|
        field_delimiter = line.index(':')
        if field_delimiter
          field_name = line[0...field_delimiter]
          field_value = line[field_delimiter + 2..line.size - 1]?
        elsif !line.empty?
          field_name = line
          field_value = lines[i + 1]?
        end

        if field_name && field_value
          case field_name
          when "id"
            id = field_value
          when "data"
            data << field_value
          when "retry"
            retry = field_value.to_i64?
          when "event"
            event = field_value
          else
            # Ignore
          end
        end
      end

      EventMessage.new(
        id: id,
        data: data,
        event: event,
        retry: retry,
      )
    end
  end

  record EventMessage,
    data : Array(String),
    event : String? = nil,
    id : String? = nil,
    retry : Int64? = nil

  abstract struct Event
    # :nodoc:
    TYPE_MAP = {} of String => self.class

    macro define(type)
      struct {{type}} < ::Anthropic::Event
        include Resource

        Event::TYPE_MAP[{{type.stringify.underscore}}] = {{type}}
        
        {{yield}}
      end
    end
  end

  Event.define ContentBlockDelta do
    getter index : Int64
    getter delta : TextDelta
  end
  Event.define ContentBlockStart do
    getter index : Int64
    getter content_block : ContentBlock?

    struct ContentBlock
      include Resource

      getter type : GeneratedMessage::Content::Type?
      getter id : String?
      getter name : String?
      getter input : JSON::Any?
    end
  end
  Event.define ContentBlockStop
  Event.define MessageDelta do
    getter delta : Delta
    getter usage : Usage

    struct Delta
      include Resource

      getter stop_reason : GeneratedMessage::StopReason?
      getter stop_sequence : String?
    end

    struct Usage
      include Resource

      getter output_tokens : Int64
    end
  end
  Event.define MessageStart do
    getter message : GeneratedMessage
  end
  Event.define MessageStop
  Event.define MessageStream
  Event.define Ping

  struct TextDelta
    include Resource

    # This is always the literal "text_delta"
    # getter type : String

    getter text : String?
  end
end
