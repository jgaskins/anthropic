module Anthropic
  private MODELS = {
    Model::Haiku     => "claude-haiku-4-5",
    Model::Sonnet    => "claude-sonnet-5",
    Model::Opus      => "claude-opus-5",
  }

  def self.model_name(model : Model)
    MODELS[model]
  end

  enum Model
    Haiku
    Sonnet
    Opus
  end
end
