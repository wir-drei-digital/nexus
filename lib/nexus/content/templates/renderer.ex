defmodule Nexus.Content.Templates.Renderer do
  @moduledoc """
  Renders template_data into HTML based on template section definitions.
  """

  import Phoenix.HTML, only: [html_escape: 1, safe_to_string: 1]

  alias Nexus.Content.Templates.{Registry, Section}
  alias Nexus.Content.TiptapRenderer

  @allowed_image_schemes ~w(http https)
  @allowed_link_schemes ~w(http https)

  @doc """
  Renders all sections of a template into a single HTML string.
  Sections are rendered in the order defined by the template.
  """
  @spec render(String.t(), map()) :: String.t()
  def render(template_slug, template_data) when is_map(template_data) do
    case Registry.get(template_slug) do
      nil ->
        ""

      template ->
        template.sections
        |> Enum.map(fn section ->
          key = Atom.to_string(section.key)
          value = Map.get(template_data, key)
          render_section(section, value)
        end)
        |> Enum.reject(&(&1 == ""))
        |> Enum.join("\n")
    end
  end

  def render(_slug, _data), do: ""

  defp render_section(_section, nil), do: ""

  defp render_section(%Section{key: key, type: :rich_text}, value) when is_map(value) do
    inner = TiptapRenderer.render(value)

    if inner == "" do
      ""
    else
      ~s(<section data-section="#{key}" data-type="rich_text">#{inner}</section>)
    end
  end

  defp render_section(%Section{key: key, type: :text}, value) when is_binary(value) do
    if value == "" do
      ""
    else
      ~s(<section data-section="#{key}" data-type="text"><p>#{escape(value)}</p></section>)
    end
  end

  defp render_section(%Section{key: key, type: :textarea}, value) when is_binary(value) do
    if value == "" do
      ""
    else
      paragraphs =
        value
        |> String.split("\n")
        |> Enum.map(&"<p>#{escape(&1)}</p>")
        |> Enum.join("\n")

      ~s(<section data-section="#{key}" data-type="textarea">#{paragraphs}</section>)
    end
  end

  defp render_section(%Section{key: key, type: :image}, value) when is_binary(value) do
    if value != "" && safe_scheme?(value, @allowed_image_schemes) do
      ~s(<section data-section="#{key}" data-type="image"><img src="#{escape(value)}" alt=""></section>)
    else
      ""
    end
  end

  defp render_section(%Section{key: key, type: :url}, value) when is_binary(value) do
    if value != "" && safe_scheme?(value, @allowed_link_schemes) do
      ~s(<section data-section="#{key}" data-type="url"><a href="#{escape(value)}">#{escape(value)}</a></section>)
    else
      ""
    end
  end

  defp render_section(%Section{key: key, type: :number}, value) when is_number(value) do
    ~s(<section data-section="#{key}" data-type="number"><span>#{value}</span></section>)
  end

  defp render_section(%Section{key: key, type: :select}, value) when is_binary(value) do
    if value == "" do
      ""
    else
      ~s(<section data-section="#{key}" data-type="select"><span>#{escape(value)}</span></section>)
    end
  end

  defp render_section(%Section{key: key, type: :toggle}, value) when is_boolean(value) do
    ~s(<section data-section="#{key}" data-type="toggle"><span>#{value}</span></section>)
  end

  defp render_section(_section, _value), do: ""

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
end
