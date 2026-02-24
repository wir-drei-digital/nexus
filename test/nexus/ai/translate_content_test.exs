defmodule Nexus.AI.TranslateContentTest do
  use ExUnit.Case, async: true

  alias Nexus.AI.Helpers

  describe "classify_fields/2" do
    test "separates translatable from direct-copy fields" do
      template_data = %{
        "body" => %{
          "type" => "doc",
          "content" => [
            %{
              "type" => "paragraph",
              "content" => [%{"type" => "text", "text" => "Hello"}]
            }
          ]
        },
        "hero_image" => "https://example.com/img.jpg",
        "cta_url" => "https://example.com",
        "featured" => true,
        "headline" => "Welcome"
      }

      field_types = %{
        "body" => :rich_text,
        "hero_image" => :image,
        "cta_url" => :url,
        "featured" => :toggle,
        "headline" => :text
      }

      {translatable, direct} = Helpers.classify_fields(template_data, field_types)

      assert Map.has_key?(translatable, "body")
      assert Map.has_key?(translatable, "headline")
      assert Map.has_key?(direct, "hero_image")
      assert Map.has_key?(direct, "cta_url")
      assert Map.has_key?(direct, "featured")
      refute Map.has_key?(translatable, "hero_image")
      refute Map.has_key?(direct, "body")
    end

    test "textarea fields are translatable" do
      {translatable, _} =
        Helpers.classify_fields(
          %{"desc" => "Some text"},
          %{"desc" => :textarea}
        )

      assert Map.has_key?(translatable, "desc")
    end

    test "select and number fields are direct-copy" do
      {_, direct} =
        Helpers.classify_fields(
          %{"count" => 5, "option" => "a"},
          %{"count" => :number, "option" => :select}
        )

      assert Map.has_key?(direct, "count")
      assert Map.has_key?(direct, "option")
    end
  end

  describe "prepare_translation_content/2" do
    test "converts rich_text fields to markdown" do
      translatable = %{
        "body" => %{
          "type" => "doc",
          "content" => [
            %{
              "type" => "paragraph",
              "content" => [%{"type" => "text", "text" => "Hello world"}]
            }
          ]
        },
        "headline" => "Welcome"
      }

      field_types = %{"body" => :rich_text, "headline" => :text}

      prepared = Helpers.prepare_translation_content(translatable, field_types)

      assert prepared["body"] == "Hello world"
      assert prepared["headline"] == "Welcome"
    end

    test "handles nil text values" do
      prepared =
        Helpers.prepare_translation_content(
          %{"title" => nil},
          %{"title" => :text}
        )

      assert prepared["title"] == ""
    end
  end

  describe "apply_translation_results/2" do
    test "converts markdown back to ProseMirror for rich_text fields" do
      results = %{
        "body" => "Hallo Welt",
        "headline" => "Willkommen"
      }

      field_types = %{"body" => :rich_text, "headline" => :text}

      applied = Helpers.apply_translation_results(results, field_types)

      assert %{"type" => "doc", "content" => _} = applied["body"]
      assert applied["headline"] == "Willkommen"
    end

    test "handles empty markdown for rich_text" do
      applied =
        Helpers.apply_translation_results(
          %{"body" => ""},
          %{"body" => :rich_text}
        )

      assert %{"type" => "doc", "content" => [%{"type" => "paragraph"}]} = applied["body"]
    end
  end
end
