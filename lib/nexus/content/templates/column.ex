defmodule Nexus.Content.Templates.Column do
  @moduledoc """
  A layout column within a Group. Contains fields that are rendered
  as a single column in a CSS grid.
  """

  alias Nexus.Content.Templates.Field

  @type t :: %__MODULE__{
          fields: [Field.t()]
        }

  defstruct fields: []
end
