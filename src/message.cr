require "./resource"
require "./message_content"

struct Anthropic::Message
  include Resource

  getter role : Role
  getter content : Array(MessageContent)

  def self.new(content : String, role : Role = :user)
    new [Text.new(content)] of MessageContent, role: role
  end

  def initialize(@content, @role = :user)
  end

  enum Role
    User
    Assistant
  end
end
