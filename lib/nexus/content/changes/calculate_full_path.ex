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
        parent_page_id = Ash.Changeset.get_attribute(changeset, :parent_page_id)

        if parent_page_id do
          case Ash.get(Nexus.Content.Page, parent_page_id, authorize?: false) do
            {:ok, page} -> to_string(page.full_path)
            _ -> nil
          end
        end

      _other ->
        nil
    end
  end
end
