defmodule Nexus.Content.Templates.Template do
  @moduledoc """
  Defines a page template — a named collection of ordered sections.
  """

  alias Nexus.Content.Templates.Section

  @type t :: %__MODULE__{
          slug: String.t(),
          label: String.t(),
          description: String.t() | nil,
          sections: [Section.t()]
        }

  @enforce_keys [:slug, :label, :sections]
  defstruct [:slug, :label, :description, sections: []]

  @doc """
  Builds the initial `template_data` map from section defaults.
  Rich text sections default to an empty TipTap doc.
  """
  @spec default_data(t()) :: map()
  def default_data(%__MODULE__{sections: sections}) do
    Map.new(sections, fn section ->
      {Atom.to_string(section.key), default_for_section(section)}
    end)
  end

  defp default_for_section(%Section{type: :rich_text, default: nil}) do
    %{"type" => "doc", "content" => [%{"type" => "paragraph"}]}
  end

  defp default_for_section(%Section{type: :toggle, default: nil}), do: false
  defp default_for_section(%Section{type: :number, default: nil}), do: nil
  defp default_for_section(%Section{default: nil}), do: nil
  defp default_for_section(%Section{default: value}), do: value

  @doc """
  Returns the section definition for the given key, or nil.
  """
  @spec get_section(t(), atom() | String.t()) :: Section.t() | nil
  def get_section(%__MODULE__{sections: sections}, key) when is_atom(key) do
    Enum.find(sections, &(&1.key == key))
  end

  def get_section(%__MODULE__{} = template, key) when is_binary(key) do
    get_section(template, String.to_existing_atom(key))
  rescue
    ArgumentError -> nil
  end
end
