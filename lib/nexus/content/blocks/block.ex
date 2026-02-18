defmodule Nexus.Content.Blocks.Block do
  use Ash.Resource,
    data_layer: :embedded

  actions do
    defaults [:read, create: :*, update: :*]
  end

  attributes do
    uuid_primary_key :id

    attribute :type, Nexus.Content.Types.BlockType do
      allow_nil? false
      public? true
    end

    attribute :data, Nexus.Content.Types.BlockData do
      allow_nil? false
      public? true
    end

    attribute :position, :integer do
      allow_nil? false
      public? true
    end
  end
end
