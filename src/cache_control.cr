require "./resource"

struct Anthropic::CacheControl
  include Resource

  getter type : Type

  def initialize(@type = :ephemeral)
  end

  enum Type
    Ephemeral
  end
end
