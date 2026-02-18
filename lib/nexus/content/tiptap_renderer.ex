defmodule Nexus.Content.TiptapRenderer do
  @moduledoc """
  Renders ProseMirror/TipTap JSON documents to sanitized HTML strings.
  """

  import Phoenix.HTML, only: [html_escape: 1, safe_to_string: 1]

  @allowed_link_schemes ~w(http https mailto tel)
  @allowed_image_schemes ~w(http https)

  @doc """
  Renders a ProseMirror JSON document to an HTML string.
  """
  @spec render(map() | nil) :: String.t()
  def render(nil), do: ""

  def render(%{"type" => "doc", "content" => content}) when is_list(content) do
    content
    |> Enum.map(&render_node/1)
    |> Enum.join("\n")
  end

  def render(%{"type" => "doc"}), do: ""
  def render(_), do: ""

  defp render_node(%{"type" => "paragraph"} = node) do
    inner = render_inline(node["content"])
    "<p>#{inner}</p>"
  end

  defp render_node(%{"type" => "heading", "attrs" => %{"level" => level}} = node)
       when level in 1..6 do
    inner = render_inline(node["content"])
    "<h#{level}>#{inner}</h#{level}>"
  end

  defp render_node(%{"type" => "bulletList"} = node) do
    items = render_children(node["content"])
    "<ul>\n#{items}\n</ul>"
  end

  defp render_node(%{"type" => "orderedList"} = node) do
    items = render_children(node["content"])
    "<ol>\n#{items}\n</ol>"
  end

  defp render_node(%{"type" => "listItem"} = node) do
    inner = render_children(node["content"])
    "<li>#{inner}</li>"
  end

  defp render_node(%{"type" => "blockquote"} = node) do
    inner = render_children(node["content"])
    "<blockquote>#{inner}</blockquote>"
  end

  defp render_node(%{"type" => "codeBlock"} = node) do
    language = get_in(node, ["attrs", "language"]) || ""
    content = render_inline(node["content"])
    lang_attr = if language != "", do: " class=\"language-#{escape(language)}\"", else: ""
    "<pre><code#{lang_attr}>#{content}</code></pre>"
  end

  defp render_node(%{"type" => "image", "attrs" => attrs}) do
    src = attrs["src"] || ""

    if safe_scheme?(src, @allowed_image_schemes) do
      "<img src=\"#{escape(src)}\" alt=\"#{escape(attrs["alt"] || "")}\">"
    else
      ""
    end
  end

  defp render_node(%{"type" => "horizontalRule"}), do: "<hr>"

  defp render_node(%{"type" => "hardBreak"}), do: "<br>"

  defp render_node(_), do: ""

  defp render_children(nil), do: ""

  defp render_children(content) when is_list(content) do
    content
    |> Enum.map(&render_node/1)
    |> Enum.join("\n")
  end

  defp render_inline(nil), do: ""

  defp render_inline(content) when is_list(content) do
    Enum.map_join(content, &render_inline_node/1)
  end

  defp render_inline_node(%{"type" => "text", "text" => text} = node) do
    escaped = escape(text)
    apply_marks(escaped, node["marks"] || [])
  end

  defp render_inline_node(%{"type" => "hardBreak"}), do: "<br>"

  defp render_inline_node(_), do: ""

  defp apply_marks(text, []), do: text

  defp apply_marks(text, [mark | rest]) do
    wrapped = wrap_mark(text, mark)
    apply_marks(wrapped, rest)
  end

  defp wrap_mark(text, %{"type" => "bold"}), do: "<strong>#{text}</strong>"
  defp wrap_mark(text, %{"type" => "italic"}), do: "<em>#{text}</em>"
  defp wrap_mark(text, %{"type" => "underline"}), do: "<u>#{text}</u>"
  defp wrap_mark(text, %{"type" => "strike"}), do: "<s>#{text}</s>"
  defp wrap_mark(text, %{"type" => "code"}), do: "<code>#{text}</code>"

  defp wrap_mark(text, %{"type" => "link", "attrs" => attrs}) do
    href = attrs["href"] || ""

    if safe_scheme?(href, @allowed_link_schemes) do
      target = if attrs["target"], do: " target=\"#{escape(attrs["target"])}\"", else: ""
      rel = if attrs["target"] == "_blank", do: " rel=\"noopener noreferrer\"", else: ""
      "<a href=\"#{escape(href)}\"#{target}#{rel}>#{text}</a>"
    else
      text
    end
  end

  defp wrap_mark(text, _), do: text

  defp safe_scheme?(url, allowed) when is_binary(url) do
    case URI.parse(url) do
      %URI{scheme: nil} -> true
      %URI{scheme: scheme} -> String.downcase(scheme) in allowed
    end
  end

  defp safe_scheme?(_, _), do: false

  defp escape(text) when is_binary(text) do
    text |> html_escape() |> safe_to_string()
  end

  defp escape(nil), do: ""
  defp escape(text), do: escape(to_string(text))
end
