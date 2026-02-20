defmodule Nexus.Content.Templates.Field do
  @moduledoc """
  Defines a single field within a page template.
  """

  @type field_type ::
          :rich_text | :text | :textarea | :image | :url | :select | :number | :toggle

  @type t :: %__MODULE__{
          key: atom(),
          type: field_type(),
          label: String.t(),
          required: boolean(),
          default: any(),
          constraints: map()
        }

  @enforce_keys [:key, :type, :label]
  defstruct [:key, :type, :label, required: false, default: nil, constraints: %{}]
end
