module Anthropic
  private MODELS = {
    Model::Haiku  => "claude-3-haiku-20240307",
    Model::Sonnet => "claude-3-sonnet-20240229",
    Model::Sonnet => "claude-3-5-sonnet-20240620",
    Model::Opus   => "claude-3-opus-20240229",
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
