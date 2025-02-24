module Anthropic
  private MODELS = {
    Model::Haiku3 => "claude-3-haiku-20240307",
    Model::Haiku  => "claude-3-5-haiku-latest",
    Model::Sonnet => "claude-3-7-sonnet-20250219",
    Model::Opus   => "claude-3-opus-20240229",
  }

  def self.model_name(model : Model)
    MODELS[model]
  end

  enum Model
    Haiku
    Haiku3
    Sonnet
    Opus
  end
end
