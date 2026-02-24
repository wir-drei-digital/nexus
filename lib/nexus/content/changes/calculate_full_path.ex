defmodule Nexus.Content.Changes.CalculateFullPath do
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      slug =
        changeset
        |> Ash.Changeset.get_attribute(:slug)
        |> to_string()
        |> slugify()

      changeset = Ash.Changeset.force_change_attribute(changeset, :slug, slug)
      parent_path = resolve_parent_path(changeset)

      full_path =
        case parent_path do
          nil -> slug
          path -> "#{path}/#{slug}"
        end

      Ash.Changeset.force_change_attribute(changeset, :full_path, full_path)
    end)
  end

  defp slugify(str) do
    str
    |> String.downcase()
    |> String.replace(~r/[^\w\s-]/u, "")
    |> String.replace(~r/[\s_]+/, "-")
    |> String.replace(~r/-+/, "-")
    |> String.trim("-")
  end

  defp resolve_parent_path(changeset) do
    case changeset.resource do
      Nexus.Content.Page ->
        resolve_page_parent_path(changeset)

      Nexus.Content.Folder ->
        resolve_folder_parent_path(changeset)

      _other ->
        nil
    end
  end

  defp resolve_page_parent_path(changeset) do
    folder_id = Ash.Changeset.get_attribute(changeset, :folder_id)
    parent_page_id = Ash.Changeset.get_attribute(changeset, :parent_page_id)

    cond do
      parent_page_id ->
        case Ash.get(Nexus.Content.Page, parent_page_id, authorize?: false) do
          {:ok, page} -> to_string(page.full_path)
          _ -> nil
        end

      folder_id ->
        case Ash.get(Nexus.Content.Folder, folder_id, authorize?: false) do
          {:ok, folder} -> to_string(folder.full_path)
          _ -> nil
        end

      true ->
        nil
    end
  end

  defp resolve_folder_parent_path(changeset) do
    parent_id = Ash.Changeset.get_attribute(changeset, :parent_id)

    if parent_id do
      case Ash.get(Nexus.Content.Folder, parent_id, authorize?: false) do
        {:ok, folder} -> to_string(folder.full_path)
        _ -> nil
      end
    end
  end
end
