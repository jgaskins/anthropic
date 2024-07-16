require "./resource"
require "./message_content"

struct Anthropic::Message
  include Resource

  getter role : Role
  getter content : String | Array(MessageContent)

  def initialize(@content, @role = :user)
  end

  enum Role
    User
    Assistant
  end
end
