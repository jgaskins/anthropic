require "./spec_helper"

describe Anthropic::Document do
  describe ".base64" do
    it "serializes a PDF document to the expected JSON structure" do
      doc = Anthropic::Document.base64(data: "hello pdf")

      json = JSON.parse(doc.to_json)

      json["type"].should eq("document")
      json["source"]["type"].should eq("base64")
      json["source"]["media_type"].should eq("application/pdf")
      json["source"]["data"].should eq(Base64.strict_encode("hello pdf"))
    end

    it "includes cache_control when set" do
      doc = Anthropic::Document.base64(
        data: "cached pdf",
        cache_control: Anthropic::CacheControl.new,
      )

      json = JSON.parse(doc.to_json)

      json["cache_control"]["type"].should eq("ephemeral")
    end

    it "omits cache_control when not set" do
      doc = Anthropic::Document.base64(data: "no cache")

      json = JSON.parse(doc.to_json)

      json["cache_control"]?.should be_nil
    end
  end

  describe "Source::MediaType" do
    it "serializes PDF as application/pdf" do
      Anthropic::Document::Source::MediaType::PDF.to_s.should eq("application/pdf")
    end
  end
end
