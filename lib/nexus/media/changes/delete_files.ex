defmodule Nexus.Media.Changes.DeleteFiles do
  @moduledoc "Deletes stored files (original + variants) when a MediaItem is destroyed."

  use Ash.Resource.Change

  alias Nexus.Media.Storage

  require Logger

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      item = changeset.data

      # Delete original
      case Storage.delete(item.file_path) do
        :ok ->
          :ok

        {:error, reason} ->
          Logger.warning("Failed to delete original #{item.file_path}: #{inspect(reason)}")
      end

      # Delete variants
      for {_name, variant_path} <- item.variants || %{} do
        case Storage.delete(variant_path) do
          :ok ->
            :ok

          {:error, reason} ->
            Logger.warning("Failed to delete variant #{variant_path}: #{inspect(reason)}")
        end
      end

      changeset
    end)
  end
end
