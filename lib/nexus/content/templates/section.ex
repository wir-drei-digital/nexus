defmodule Nexus.Content.Templates.Section do
  @moduledoc """
  Defines a single section within a page template.
  """

  @type section_type ::
          :rich_text | :text | :textarea | :image | :url | :select | :number | :toggle

  @type t :: %__MODULE__{
          key: atom(),
          type: section_type(),
          label: String.t(),
          required: boolean(),
          default: any(),
          constraints: map()
        }

  @enforce_keys [:key, :type, :label]
  defstruct [:key, :type, :label, required: false, default: nil, constraints: %{}]

  @valid_types ~w(rich_text text textarea image url select number toggle)a

  def valid_types, do: @valid_types

  def valid_type?(type), do: type in @valid_types
end
