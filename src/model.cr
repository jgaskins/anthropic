module Anthropic
  private MODELS = {
    Model::Haiku     => "claude-3-5-haiku-latest",
    Model::Haiku3    => "claude-3-haiku-20240307",
    Model::Sonnet    => "claude-sonnet-4-20250514",
    Model::Sonnet3_5 => "claude-3-5-sonnet-20241022",
    Model::Sonnet3_7 => "claude-3-7-sonnet-20250219",
    Model::Opus      => "claude-opus-4-20250514",
    Model::Opus3     => "claude-3-opus-20240229",
  }

  def self.model_name(model : Model)
    MODELS[model]
  end

  enum Model
    Haiku
    Haiku3
    Sonnet
    Sonnet3_5
    Sonnet3_7
    Opus
    Opus3
  end
end
