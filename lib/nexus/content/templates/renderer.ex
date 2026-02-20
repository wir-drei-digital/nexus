defmodule Nexus.Content.Templates.Renderer do
  @moduledoc """
  Renders template_data into HTML based on template field definitions.
  """

  import Phoenix.HTML, only: [html_escape: 1, safe_to_string: 1]

  alias Nexus.Content.Templates.{Field, Registry, Template}
  alias TiptapPhoenix.Renderer, as: TiptapRenderer

  @allowed_image_schemes ~w(http https)
  @allowed_link_schemes ~w(http https)

  @doc """
  Renders all fields of a template into a single HTML string.
  Fields are rendered in the order defined by the template,
  with groups and columns flattened.
  """
  @spec render(String.t(), map()) :: String.t()
  def render(template_slug, template_data) when is_map(template_data) do
    case Registry.get(template_slug) do
      nil ->
        ""

      template ->
        template
        |> Template.all_fields()
        |> Enum.map(fn field ->
          key = Atom.to_string(field.key)
          value = Map.get(template_data, key)
          render_field(field, value)
        end)
        |> Enum.reject(&(&1 == ""))
        |> Enum.join("\n")
    end
  end

  def render(_slug, _data), do: ""

  defp render_field(_field, nil), do: ""

  defp render_field(%Field{key: key, type: :rich_text}, value) when is_map(value) do
    inner = TiptapRenderer.render(value)

    if inner == "" do
      ""
    else
      ~s(<section data-field="#{key}" data-type="rich_text">#{inner}</section>)
    end
  end

  defp render_field(%Field{key: key, type: :text}, value) when is_binary(value) do
    if value == "" do
      ""
    else
      ~s(<section data-field="#{key}" data-type="text"><p>#{escape(value)}</p></section>)
    end
  end

  defp render_field(%Field{key: key, type: :textarea}, value) when is_binary(value) do
    if value == "" do
      ""
    else
      paragraphs =
        value
        |> String.split("\n")
        |> Enum.map(&"<p>#{escape(&1)}</p>")
        |> Enum.join("\n")

      ~s(<section data-field="#{key}" data-type="textarea">#{paragraphs}</section>)
    end
  end

  defp render_field(%Field{key: key, type: :image}, value) when is_binary(value) do
    if value != "" && safe_scheme?(value, @allowed_image_schemes) do
      ~s(<section data-field="#{key}" data-type="image"><img src="#{escape(value)}" alt=""></section>)
    else
      ""
    end
  end

  defp render_field(%Field{key: key, type: :url}, value) when is_binary(value) do
    if value != "" && safe_scheme?(value, @allowed_link_schemes) do
      ~s(<section data-field="#{key}" data-type="url"><a href="#{escape(value)}">#{escape(value)}</a></section>)
    else
      ""
    end
  end

  defp render_field(%Field{key: key, type: :number}, value) when is_number(value) do
    ~s(<section data-field="#{key}" data-type="number"><span>#{value}</span></section>)
  end

  defp render_field(%Field{key: key, type: :select}, value) when is_binary(value) do
    if value == "" do
      ""
    else
      ~s(<section data-field="#{key}" data-type="select"><span>#{escape(value)}</span></section>)
    end
  end

  defp render_field(%Field{key: key, type: :toggle}, value) when is_boolean(value) do
    ~s(<section data-field="#{key}" data-type="toggle"><span>#{value}</span></section>)
  end

  defp render_field(_field, _value), do: ""

  defp safe_scheme?(url, allowed) when is_binary(url) do
    case URI.new(url) do
      {:ok, %URI{scheme: scheme}} when is_binary(scheme) ->
        String.downcase(scheme) in allowed

      _ ->
        false
    end
  end

  defp safe_scheme?(_, _), do: false

  defp escape(text) when is_binary(text) do
    text |> html_escape() |> safe_to_string()
  end

  defp escape(nil), do: ""
end
