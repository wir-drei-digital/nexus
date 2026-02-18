defmodule Nexus.Content.BlockRenderer do
  @moduledoc """
  Renders block arrays to sanitized HTML strings.
  """

  import Phoenix.HTML, only: [html_escape: 1, safe_to_string: 1]

  def render_blocks(blocks) when is_list(blocks) do
    blocks
    |> Enum.sort_by(& &1.position)
    |> Enum.map(&render_block/1)
    |> Enum.join("\n")
  end

  def render_blocks(_), do: ""

  defp render_block(%{type: :text, data: %{value: %{content: content}}}) do
    "<p>#{escape(content)}</p>"
  end

  defp render_block(%{type: :heading, data: %{value: %{content: content, level: level}}})
       when level in 1..6 do
    "<h#{level}>#{escape(content)}</h#{level}>"
  end

  defp render_block(%{type: :image, data: %{value: data}}) do
    alt = escape(Map.get(data, :alt, ""))
    url = escape(data.url)
    caption = Map.get(data, :caption)

    fig =
      if caption do
        "<figure><img src=\"#{url}\" alt=\"#{alt}\"><figcaption>#{escape(caption)}</figcaption></figure>"
      else
        "<img src=\"#{url}\" alt=\"#{alt}\">"
      end

    fig
  end

  defp render_block(%{type: :code, data: %{value: data}}) do
    lang = Map.get(data, :language, "")
    lang_attr = if lang != "", do: " class=\"language-#{escape(lang)}\"", else: ""
    "<pre><code#{lang_attr}>#{escape(data.content)}</code></pre>"
  end

  defp render_block(%{type: :quote, data: %{value: data}}) do
    attribution = Map.get(data, :attribution)

    cite =
      if attribution do
        "<footer>#{escape(attribution)}</footer>"
      else
        ""
      end

    "<blockquote><p>#{escape(data.content)}</p>#{cite}</blockquote>"
  end

  defp render_block(%{type: :list, data: %{value: %{style: style, items: items}}}) do
    tag = if style == :ordered, do: "ol", else: "ul"
    lis = Enum.map_join(items, "\n", fn item -> "<li>#{escape(item)}</li>" end)
    "<#{tag}>\n#{lis}\n</#{tag}>"
  end

  defp render_block(%{type: :divider}) do
    "<hr>"
  end

  defp render_block(_block), do: ""

  defp escape(text) when is_binary(text) do
    text |> html_escape() |> safe_to_string()
  end

  defp escape(nil), do: ""
  defp escape(text), do: escape(to_string(text))
end
