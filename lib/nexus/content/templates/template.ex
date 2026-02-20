defmodule Nexus.Content.Templates.Template do
  @moduledoc """
  Defines a page template — a named collection of fields, optionally
  organized into groups and columns for layout.
  """

  alias Nexus.Content.Templates.{Column, Field, Group}

  @type template_item :: Field.t() | Group.t()

  @type t :: %__MODULE__{
          slug: String.t(),
          label: String.t(),
          description: String.t() | nil,
          fields: [template_item()]
        }

  @enforce_keys [:slug, :label, :fields]
  defstruct [:slug, :label, :description, fields: []]

  @doc """
  Builds the initial `template_data` map from field defaults.
  Rich text fields default to an empty TipTap doc.
  """
  @spec default_data(t()) :: map()
  def default_data(%__MODULE__{fields: items}) do
    items
    |> all_fields()
    |> Map.new(fn field ->
      {Atom.to_string(field.key), default_for_field(field)}
    end)
  end

  @doc """
  Returns the field definition for the given key, or nil.
  Searches through groups and columns recursively.
  """
  @spec get_field(t(), atom() | String.t()) :: Field.t() | nil
  def get_field(%__MODULE__{fields: items}, key) when is_atom(key) do
    items
    |> all_fields()
    |> Enum.find(&(&1.key == key))
  end

  def get_field(%__MODULE__{} = template, key) when is_binary(key) do
    template
    |> all_fields()
    |> Enum.find(&(Atom.to_string(&1.key) == key))
  end

  @doc """
  Extracts all `Field` structs from the template, flattening through
  any Group/Column nesting.
  """
  @spec all_fields([template_item()] | t()) :: [Field.t()]
  def all_fields(%__MODULE__{fields: items}), do: all_fields(items)

  def all_fields(items) when is_list(items) do
    Enum.flat_map(items, fn
      %Field{} = field -> [field]
      %Group{columns: columns} -> Enum.flat_map(columns, &all_fields_from_column/1)
    end)
  end

  defp all_fields_from_column(%Column{fields: fields}), do: fields

  defp default_for_field(%Field{type: :rich_text, default: nil}) do
    %{"type" => "doc", "content" => [%{"type" => "paragraph"}]}
  end

  defp default_for_field(%Field{type: :toggle, default: nil}), do: false
  defp default_for_field(%Field{default: nil}), do: nil
  defp default_for_field(%Field{default: value}), do: value
end
