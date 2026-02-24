defmodule Nexus.AI.ProseMirror do
  @moduledoc """
  Converts between Markdown and ProseMirror JSON (TipTap document format).

  Uses MDEx to parse markdown into an AST, then walks the AST to produce
  ProseMirror-compatible JSON maps with string keys.

  ## ProseMirror JSON structure

  Documents are nested maps with string keys:

      %{"type" => "doc", "content" => [
        %{"type" => "paragraph", "content" => [
          %{"type" => "text", "text" => "Hello "},
          %{"type" => "text", "text" => "world", "marks" => [%{"type" => "bold"}]}
        ]}
      ]}
  """

  @mdex_extensions [
    table: true,
    tasklist: true,
    strikethrough: true
  ]

  @doc """
  Converts a markdown string to a ProseMirror JSON document.
  """
  @spec from_markdown(String.t()) :: {:ok, map()} | {:error, term()}
  def from_markdown(markdown) when is_binary(markdown) do
    markdown = String.trim(markdown)

    if markdown == "" do
      {:ok, default_doc()}
    else
      case MDEx.parse_document(markdown, extension: @mdex_extensions) do
        {:ok, doc} ->
          content = convert_nodes(doc.nodes)
          content = if content == [], do: [%{"type" => "paragraph"}], else: content
          {:ok, %{"type" => "doc", "content" => content}}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @doc """
  Converts a ProseMirror JSON document to plain text (no formatting).
  """
  @spec to_plain_text(map()) :: String.t()
  def to_plain_text(%{"type" => "doc", "content" => content}) when is_list(content) do
    content
    |> Enum.map(&node_to_plain_text/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n")
  end

  def to_plain_text(%{"type" => "doc"}), do: ""
  def to_plain_text(_), do: ""

  @doc """
  Converts a ProseMirror JSON document to a Markdown string.
  Used for feeding rich text content to LLMs for translation.
  """
  @spec to_markdown(map() | nil) :: String.t()
  def to_markdown(nil), do: ""

  def to_markdown(%{"type" => "doc", "content" => content}) when is_list(content) do
    content
    |> Enum.map(&node_to_markdown/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n\n")
  end

  def to_markdown(%{"type" => "doc"}), do: ""
  def to_markdown(_), do: ""

  @doc """
  Extracts plain text from a ProseMirror JSON document, a JSON-encoded string,
  or a template_data map (extracting text from all rich text fields).
  """
  @spec extract_text(term()) :: String.t()
  def extract_text(nil), do: ""
  def extract_text(""), do: ""

  def extract_text(doc) when is_binary(doc) do
    case Jason.decode(doc) do
      {:ok, %{"type" => "doc"} = parsed} -> to_plain_text(parsed)
      {:ok, parsed} when is_map(parsed) -> extract_text_from_template_data(parsed)
      {:error, _} -> doc
    end
  end

  def extract_text(%{"type" => "doc"} = doc), do: to_plain_text(doc)

  def extract_text(doc) when is_map(doc), do: extract_text_from_template_data(doc)

  def extract_text(_), do: ""

  @doc """
  Returns an empty ProseMirror document.
  """
  @spec default_doc() :: map()
  def default_doc do
    %{"type" => "doc", "content" => [%{"type" => "paragraph"}]}
  end

  # Extract text from template_data map (multiple fields)
  defp extract_text_from_template_data(data) when is_map(data) do
    data
    |> Enum.map(fn
      {_key, %{"type" => "doc"} = doc} -> to_plain_text(doc)
      _ -> ""
    end)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n\n")
  end

  # ---------------------------------------------------------------------------
  # MDEx AST → ProseMirror JSON
  # ---------------------------------------------------------------------------

  defp convert_nodes(nodes) when is_list(nodes) do
    Enum.flat_map(nodes, &convert_node/1)
  end

  defp convert_node(%MDEx.Paragraph{nodes: children}) do
    content = convert_inline_nodes(children, [])
    [%{"type" => "paragraph"} |> maybe_add_content(content)]
  end

  defp convert_node(%MDEx.Heading{level: level, nodes: children}) do
    content = convert_inline_nodes(children, [])

    [
      %{"type" => "heading", "attrs" => %{"level" => level}}
      |> maybe_add_content(content)
    ]
  end

  defp convert_node(%MDEx.CodeBlock{info: info, literal: literal}) do
    language = if info != "" and info != nil, do: info, else: nil
    text_content = String.trim_trailing(literal, "\n")

    node = %{"type" => "codeBlock"}
    node = if language, do: Map.put(node, "attrs", %{"language" => language}), else: node

    node =
      if text_content != "" do
        Map.put(node, "content", [%{"type" => "text", "text" => text_content}])
      else
        node
      end

    [node]
  end

  defp convert_node(%MDEx.BlockQuote{nodes: children}) do
    content = convert_nodes(children)
    [%{"type" => "blockquote", "content" => content}]
  end

  defp convert_node(%MDEx.List{list_type: list_type, nodes: children}) do
    type = if list_type == :bullet, do: "bulletList", else: "orderedList"
    content = convert_nodes(children)
    [%{"type" => type, "content" => content}]
  end

  defp convert_node(%MDEx.ListItem{nodes: children}) do
    content = convert_nodes(children)
    [%{"type" => "listItem", "content" => content}]
  end

  defp convert_node(%MDEx.TaskItem{checked: checked, nodes: children}) do
    content = convert_nodes(children)
    [%{"type" => "taskItem", "attrs" => %{"checked" => checked}, "content" => content}]
  end

  defp convert_node(%MDEx.Table{nodes: rows}) do
    content = convert_nodes(rows)
    [%{"type" => "table", "content" => content}]
  end

  defp convert_node(%MDEx.TableRow{header: header, nodes: cells}) do
    content =
      Enum.flat_map(cells, fn cell ->
        cell_type = if header, do: "tableHeader", else: "tableCell"
        cell_content = convert_inline_nodes(cell.nodes, [])

        inner =
          if cell_content == [],
            do: [%{"type" => "paragraph"}],
            else: [%{"type" => "paragraph", "content" => cell_content}]

        [
          %{
            "type" => cell_type,
            "attrs" => %{"colspan" => 1, "rowspan" => 1},
            "content" => inner
          }
        ]
      end)

    [%{"type" => "tableRow", "content" => content}]
  end

  defp convert_node(%MDEx.ThematicBreak{}) do
    [%{"type" => "horizontalRule"}]
  end

  defp convert_node(%MDEx.HtmlBlock{literal: literal}) do
    if String.trim(literal) == "" do
      []
    else
      [
        %{
          "type" => "paragraph",
          "content" => [%{"type" => "text", "text" => String.trim(literal)}]
        }
      ]
    end
  end

  defp convert_node(%MDEx.Text{} = node) do
    convert_inline_nodes([node], [])
  end

  defp convert_node(_unknown), do: []

  # ---------------------------------------------------------------------------
  # Inline nodes with mark accumulation
  # ---------------------------------------------------------------------------

  defp convert_inline_nodes(nodes, marks) when is_list(nodes) do
    Enum.flat_map(nodes, &convert_inline_node(&1, marks))
  end

  defp convert_inline_node(%MDEx.Text{literal: literal}, marks) do
    node = %{"type" => "text", "text" => literal}
    [maybe_add_marks(node, marks)]
  end

  defp convert_inline_node(%MDEx.Strong{nodes: children}, marks) do
    convert_inline_nodes(children, marks ++ [%{"type" => "bold"}])
  end

  defp convert_inline_node(%MDEx.Emph{nodes: children}, marks) do
    convert_inline_nodes(children, marks ++ [%{"type" => "italic"}])
  end

  defp convert_inline_node(%MDEx.Strikethrough{nodes: children}, marks) do
    convert_inline_nodes(children, marks ++ [%{"type" => "strike"}])
  end

  defp convert_inline_node(%MDEx.Link{url: url, nodes: children}, marks) do
    link_mark = %{"type" => "link", "attrs" => %{"href" => url}}
    convert_inline_nodes(children, marks ++ [link_mark])
  end

  defp convert_inline_node(%MDEx.Code{literal: literal}, marks) do
    node = %{"type" => "text", "text" => literal}
    [maybe_add_marks(node, marks ++ [%{"type" => "code"}])]
  end

  defp convert_inline_node(%MDEx.Image{url: url, title: title, nodes: children}, _marks) do
    alt = extract_text_from_mdex_nodes(children)

    attrs = %{"src" => url}
    attrs = if alt != "", do: Map.put(attrs, "alt", alt), else: attrs
    attrs = if title != "" and title != nil, do: Map.put(attrs, "title", title), else: attrs

    [%{"type" => "image", "attrs" => attrs}]
  end

  defp convert_inline_node(%MDEx.SoftBreak{}, marks) do
    node = %{"type" => "text", "text" => " "}
    [maybe_add_marks(node, marks)]
  end

  defp convert_inline_node(%MDEx.LineBreak{}, _marks) do
    [%{"type" => "hardBreak"}]
  end

  defp convert_inline_node(%MDEx.HtmlInline{literal: literal}, marks) do
    node = %{"type" => "text", "text" => literal}
    [maybe_add_marks(node, marks)]
  end

  defp convert_inline_node(_unknown, _marks), do: []

  # ---------------------------------------------------------------------------
  # ProseMirror JSON → Plain Text
  # ---------------------------------------------------------------------------

  defp node_to_plain_text(%{"type" => "paragraph", "content" => content}) do
    extract_inline_text(content)
  end

  defp node_to_plain_text(%{"type" => "paragraph"}), do: ""

  defp node_to_plain_text(%{"type" => "heading", "content" => content}) do
    extract_inline_text(content)
  end

  defp node_to_plain_text(%{"type" => "heading"}), do: ""

  defp node_to_plain_text(%{"type" => "codeBlock", "content" => [%{"text" => text}]}) do
    text
  end

  defp node_to_plain_text(%{"type" => "codeBlock"}), do: ""

  defp node_to_plain_text(%{"type" => "blockquote", "content" => content}) do
    content
    |> Enum.map(&node_to_plain_text/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n")
  end

  defp node_to_plain_text(%{"type" => type, "content" => items})
       when type in ["bulletList", "orderedList"] do
    items
    |> Enum.map(&node_to_plain_text/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n")
  end

  defp node_to_plain_text(%{"type" => type, "content" => content})
       when type in ["listItem", "taskItem"] do
    content
    |> Enum.map(&node_to_plain_text/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n")
  end

  defp node_to_plain_text(%{"type" => "table", "content" => rows}) do
    rows
    |> Enum.map(fn %{"content" => cells} ->
      cells
      |> Enum.map(fn cell ->
        (cell["content"] || [])
        |> Enum.map(&node_to_plain_text/1)
        |> Enum.join(" ")
        |> String.trim()
      end)
      |> Enum.join(" | ")
    end)
    |> Enum.join("\n")
  end

  defp node_to_plain_text(%{"type" => "horizontalRule"}), do: "---"

  defp node_to_plain_text(%{"type" => "image", "attrs" => attrs}) do
    attrs["alt"] || ""
  end

  defp node_to_plain_text(_), do: ""

  # ---------------------------------------------------------------------------
  # ProseMirror JSON → Markdown
  # ---------------------------------------------------------------------------

  defp node_to_markdown(%{"type" => "paragraph", "content" => content}) do
    inline_to_markdown(content)
  end

  defp node_to_markdown(%{"type" => "paragraph"}), do: ""

  defp node_to_markdown(%{
         "type" => "heading",
         "attrs" => %{"level" => level},
         "content" => content
       }) do
    prefix = String.duplicate("#", level)
    "#{prefix} #{inline_to_markdown(content)}"
  end

  defp node_to_markdown(%{"type" => "heading"}), do: ""

  defp node_to_markdown(%{
         "type" => "codeBlock",
         "attrs" => %{"language" => lang},
         "content" => [%{"text" => text}]
       })
       when is_binary(lang) and lang != "" do
    "```#{lang}\n#{text}\n```"
  end

  defp node_to_markdown(%{"type" => "codeBlock", "content" => [%{"text" => text}]}) do
    "```\n#{text}\n```"
  end

  defp node_to_markdown(%{"type" => "codeBlock"}) do
    "```\n\n```"
  end

  defp node_to_markdown(%{"type" => "blockquote", "content" => content}) do
    content
    |> Enum.map(fn node ->
      node
      |> node_to_markdown()
      |> String.split("\n")
      |> Enum.map_join("\n", &"> #{&1}")
    end)
    |> Enum.join("\n>\n")
  end

  defp node_to_markdown(%{"type" => "bulletList", "content" => items}) do
    items
    |> Enum.map(fn item -> "- #{list_item_to_markdown(item)}" end)
    |> Enum.join("\n")
  end

  defp node_to_markdown(%{"type" => "orderedList", "content" => items}) do
    items
    |> Enum.with_index(1)
    |> Enum.map(fn {item, idx} -> "#{idx}. #{list_item_to_markdown(item)}" end)
    |> Enum.join("\n")
  end

  defp node_to_markdown(%{"type" => "horizontalRule"}), do: "---"

  defp node_to_markdown(%{"type" => "image", "attrs" => attrs}) do
    alt = attrs["alt"] || ""
    src = attrs["src"] || ""
    "![#{alt}](#{src})"
  end

  defp node_to_markdown(_), do: ""

  defp list_item_to_markdown(%{"type" => "listItem", "content" => content}) do
    content
    |> Enum.map(&node_to_markdown/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n")
  end

  defp list_item_to_markdown(_), do: ""

  defp inline_to_markdown(nodes) when is_list(nodes) do
    Enum.map_join(nodes, "", &inline_node_to_markdown/1)
  end

  defp inline_node_to_markdown(%{"type" => "text", "text" => text, "marks" => marks})
       when is_list(marks) do
    wrap_with_marks(text, marks)
  end

  defp inline_node_to_markdown(%{"type" => "text", "text" => text}), do: text

  defp inline_node_to_markdown(%{"type" => "hardBreak"}), do: "\n"

  defp inline_node_to_markdown(_), do: ""

  defp wrap_with_marks(text, []), do: text

  defp wrap_with_marks(text, [%{"type" => "link", "attrs" => %{"href" => href}} | rest]) do
    wrap_with_marks("[#{text}](#{href})", rest)
  end

  defp wrap_with_marks(text, [%{"type" => "bold"} | rest]) do
    wrap_with_marks("**#{text}**", rest)
  end

  defp wrap_with_marks(text, [%{"type" => "italic"} | rest]) do
    wrap_with_marks("*#{text}*", rest)
  end

  defp wrap_with_marks(text, [%{"type" => "strike"} | rest]) do
    wrap_with_marks("~~#{text}~~", rest)
  end

  defp wrap_with_marks(text, [%{"type" => "code"} | rest]) do
    wrap_with_marks("`#{text}`", rest)
  end

  defp wrap_with_marks(text, [_ | rest]), do: wrap_with_marks(text, rest)

  defp extract_inline_text(nodes) when is_list(nodes) do
    Enum.map_join(nodes, "", fn
      %{"type" => "text", "text" => text} -> text
      %{"type" => "hardBreak"} -> "\n"
      _ -> ""
    end)
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp maybe_add_content(node, []), do: node
  defp maybe_add_content(node, content), do: Map.put(node, "content", content)

  defp maybe_add_marks(node, []), do: node
  defp maybe_add_marks(node, marks), do: Map.put(node, "marks", marks)

  defp extract_text_from_mdex_nodes(nodes) when is_list(nodes) do
    Enum.map_join(nodes, "", fn
      %MDEx.Text{literal: literal} -> literal
      _ -> ""
    end)
  end

  defp extract_text_from_mdex_nodes(_), do: ""
end
