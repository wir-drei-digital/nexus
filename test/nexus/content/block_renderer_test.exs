defmodule Nexus.Content.BlockRendererTest do
  use ExUnit.Case, async: true

  alias Nexus.Content.BlockRenderer

  defp block(type, data, position \\ 0) do
    %{id: Ash.UUID.generate(), type: type, data: data, position: position}
  end

  describe "render_blocks/1" do
    test "renders text block" do
      blocks = [block(:text, %{value: %{content: "Hello world"}})]
      assert BlockRenderer.render_blocks(blocks) =~ "<p>Hello world</p>"
    end

    test "renders heading block" do
      blocks = [block(:heading, %{value: %{content: "Title", level: 1}})]
      assert BlockRenderer.render_blocks(blocks) =~ "<h1>Title</h1>"
    end

    test "renders heading with different levels" do
      blocks = [block(:heading, %{value: %{content: "Sub", level: 3}})]
      assert BlockRenderer.render_blocks(blocks) =~ "<h3>Sub</h3>"
    end

    test "renders image block without caption" do
      blocks = [block(:image, %{value: %{url: "https://example.com/img.jpg", alt: "Photo"}})]
      html = BlockRenderer.render_blocks(blocks)
      assert html =~ ~s(<img src="https://example.com/img.jpg" alt="Photo">)
    end

    test "renders image block with caption" do
      blocks = [
        block(:image, %{
          value: %{url: "https://example.com/img.jpg", alt: "Photo", caption: "A photo"}
        })
      ]

      html = BlockRenderer.render_blocks(blocks)
      assert html =~ "<figure>"
      assert html =~ "<figcaption>A photo</figcaption>"
    end

    test "renders code block" do
      blocks = [block(:code, %{value: %{content: "x = 1", language: "elixir"}})]
      html = BlockRenderer.render_blocks(blocks)
      assert html =~ "<pre><code"
      assert html =~ "language-elixir"
      assert html =~ "x = 1"
    end

    test "renders quote block" do
      blocks = [
        block(:quote, %{value: %{content: "Be yourself", attribution: "Oscar Wilde"}})
      ]

      html = BlockRenderer.render_blocks(blocks)
      assert html =~ "<blockquote>"
      assert html =~ "Be yourself"
      assert html =~ "Oscar Wilde"
    end

    test "renders list block" do
      blocks = [
        block(:list, %{value: %{style: :unordered, items: ["One", "Two", "Three"]}})
      ]

      html = BlockRenderer.render_blocks(blocks)
      assert html =~ "<ul>"
      assert html =~ "<li>One</li>"
      assert html =~ "<li>Three</li>"
    end

    test "renders ordered list" do
      blocks = [
        block(:list, %{value: %{style: :ordered, items: ["First", "Second"]}})
      ]

      html = BlockRenderer.render_blocks(blocks)
      assert html =~ "<ol>"
    end

    test "renders divider" do
      blocks = [block(:divider, %{value: %{}})]
      assert BlockRenderer.render_blocks(blocks) =~ "<hr>"
    end

    test "escapes HTML in content" do
      blocks = [block(:text, %{value: %{content: "<script>alert('xss')</script>"}})]
      html = BlockRenderer.render_blocks(blocks)
      refute html =~ "<script>"
      assert html =~ "&lt;script&gt;"
    end

    test "renders blocks in position order" do
      blocks = [
        block(:text, %{value: %{content: "Second"}}, 1),
        block(:text, %{value: %{content: "First"}}, 0)
      ]

      html = BlockRenderer.render_blocks(blocks)
      first_idx = :binary.match(html, "First") |> elem(0)
      second_idx = :binary.match(html, "Second") |> elem(0)
      assert first_idx < second_idx
    end

    test "returns empty string for nil" do
      assert BlockRenderer.render_blocks(nil) == ""
    end
  end
end
