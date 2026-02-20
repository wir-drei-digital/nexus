defmodule Nexus.Content.Templates.Group do
  @moduledoc """
  Groups multiple fields together under a label, arranged in columns.
  Rendered as a CSS grid in the UI.
  """

  alias Nexus.Content.Templates.Column

  @type t :: %__MODULE__{
          key: atom(),
          label: String.t(),
          columns: [Column.t()]
        }

  @enforce_keys [:key, :label, :columns]
  defstruct [:key, :label, columns: []]
end
