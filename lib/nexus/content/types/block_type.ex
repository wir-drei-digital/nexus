defmodule Nexus.Content.Types.BlockType do
  use Ash.Type.Enum,
    values: [
      :text,
      :heading,
      :image,
      :code,
      :quote,
      :list,
      :divider
    ]
end
