defmodule Nexus.Content.Changes.CalculateFullPath do
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      slug = Ash.Changeset.get_attribute(changeset, :slug)
      parent_path = resolve_parent_path(changeset)

      full_path =
        case parent_path do
          nil -> to_string(slug)
          path -> "#{path}/#{slug}"
        end

      Ash.Changeset.force_change_attribute(changeset, :full_path, full_path)
    end)
  end

  defp resolve_parent_path(changeset) do
    resource = changeset.resource

    cond do
      resource == Nexus.Content.Folder ->
        resolve_folder_parent(changeset)

      resource == Nexus.Content.Page ->
        resolve_page_parent(changeset)

      true ->
        nil
    end
  end

  defp resolve_folder_parent(changeset) do
    parent_id = Ash.Changeset.get_attribute(changeset, :parent_id)

    if parent_id do
      case Ash.get(Nexus.Content.Folder, parent_id, authorize?: false) do
        {:ok, parent} -> to_string(parent.full_path)
        _ -> nil
      end
    end
  end

  defp resolve_page_parent(changeset) do
    folder_id = Ash.Changeset.get_attribute(changeset, :folder_id)
    parent_page_id = Ash.Changeset.get_attribute(changeset, :parent_page_id)

    parts =
      [
        if(folder_id, do: get_folder_path(folder_id)),
        if(parent_page_id, do: get_page_path(parent_page_id))
      ]
      |> Enum.reject(&is_nil/1)

    case parts do
      [] -> nil
      paths -> Enum.join(paths, "/")
    end
  end

  defp get_folder_path(folder_id) do
    case Ash.get(Nexus.Content.Folder, folder_id, authorize?: false) do
      {:ok, folder} -> to_string(folder.full_path)
      _ -> nil
    end
  end

  defp get_page_path(page_id) do
    case Ash.get(Nexus.Content.Page, page_id, authorize?: false) do
      {:ok, page} -> to_string(page.full_path)
      _ -> nil
    end
  end
end
