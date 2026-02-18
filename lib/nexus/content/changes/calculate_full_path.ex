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
      resource == Nexus.Content.Directory ->
        resolve_directory_parent(changeset)

      resource == Nexus.Content.Page ->
        resolve_page_parent(changeset)

      true ->
        nil
    end
  end

  defp resolve_directory_parent(changeset) do
    parent_id = Ash.Changeset.get_attribute(changeset, :parent_id)

    if parent_id do
      case Ash.get(Nexus.Content.Directory, parent_id, authorize?: false) do
        {:ok, parent} -> to_string(parent.full_path)
        _ -> nil
      end
    end
  end

  defp resolve_page_parent(changeset) do
    directory_id = Ash.Changeset.get_attribute(changeset, :directory_id)
    parent_page_id = Ash.Changeset.get_attribute(changeset, :parent_page_id)

    parts =
      [
        if(directory_id, do: get_directory_path(directory_id)),
        if(parent_page_id, do: get_page_path(parent_page_id))
      ]
      |> Enum.reject(&is_nil/1)

    case parts do
      [] -> nil
      paths -> Enum.join(paths, "/")
    end
  end

  defp get_directory_path(directory_id) do
    case Ash.get(Nexus.Content.Directory, directory_id, authorize?: false) do
      {:ok, dir} -> to_string(dir.full_path)
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
