defmodule Nexus.Content.Templates.Validator do
  @moduledoc """
  Validates `template_data` against a template's section definitions.
  """

  alias Nexus.Content.Templates.{Registry, Section, Template}

  @doc """
  Validates template_data against the template identified by slug.
  Returns :ok or {:error, errors} where errors is a list of {key, message} tuples.
  """
  @spec validate(String.t(), map()) :: :ok | {:error, [{String.t(), String.t()}]}
  def validate(template_slug, template_data) when is_map(template_data) do
    case Registry.get(template_slug) do
      nil ->
        {:error, [{"template_slug", "template '#{template_slug}' does not exist"}]}

      template ->
        validate_against_template(template, template_data)
    end
  end

  def validate(_slug, _data), do: {:error, [{"template_data", "must be a map"}]}

  @spec validate_against_template(Template.t(), map()) ::
          :ok | {:error, [{String.t(), String.t()}]}
  defp validate_against_template(%Template{sections: sections}, data) do
    errors =
      Enum.flat_map(sections, fn section ->
        key = Atom.to_string(section.key)
        value = Map.get(data, key)
        validate_section_value(section, key, value)
      end)

    case errors do
      [] -> :ok
      errors -> {:error, errors}
    end
  end

  defp validate_section_value(%Section{required: true}, key, nil) do
    [{key, "is required"}]
  end

  defp validate_section_value(%Section{required: true, type: :rich_text}, key, value) do
    if empty_rich_text?(value) do
      [{key, "is required"}]
    else
      []
    end
  end

  defp validate_section_value(_section, _key, nil), do: []

  defp validate_section_value(%Section{type: type}, key, value) do
    validate_type(type, key, value)
  end

  defp validate_type(:rich_text, key, value) when is_map(value) do
    if Map.has_key?(value, "type") do
      []
    else
      [{key, "must be a valid TipTap document"}]
    end
  end

  defp validate_type(:rich_text, key, _), do: [{key, "must be a valid TipTap document"}]

  defp validate_type(:text, _key, value) when is_binary(value), do: []
  defp validate_type(:text, key, _), do: [{key, "must be a string"}]

  defp validate_type(:textarea, _key, value) when is_binary(value), do: []
  defp validate_type(:textarea, key, _), do: [{key, "must be a string"}]

  defp validate_type(:image, key, value) when is_binary(value) do
    if valid_url?(value), do: [], else: [{key, "must be a valid URL"}]
  end

  defp validate_type(:image, key, _), do: [{key, "must be a valid image URL"}]

  defp validate_type(:url, key, value) when is_binary(value) do
    if valid_url?(value), do: [], else: [{key, "must be a valid URL"}]
  end

  defp validate_type(:url, key, _), do: [{key, "must be a valid URL"}]

  defp validate_type(:number, _key, value) when is_number(value), do: []
  defp validate_type(:number, key, _), do: [{key, "must be a number"}]

  defp validate_type(:toggle, _key, value) when is_boolean(value), do: []
  defp validate_type(:toggle, key, _), do: [{key, "must be a boolean"}]

  defp validate_type(:select, _key, value) when is_binary(value), do: []
  defp validate_type(:select, key, _), do: [{key, "must be a string"}]

  defp valid_url?(url) do
    case URI.parse(url) do
      %URI{scheme: scheme} when scheme in ["http", "https"] -> true
      _ -> false
    end
  end

  defp empty_rich_text?(%{"type" => "doc", "content" => []}), do: true
  defp empty_rich_text?(%{"type" => "doc", "content" => nil}), do: true
  defp empty_rich_text?(%{"type" => "doc"} = doc) when not is_map_key(doc, "content"), do: true
  defp empty_rich_text?(_), do: false
end
