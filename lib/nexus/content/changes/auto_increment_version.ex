defmodule Nexus.Content.Changes.AutoIncrementVersion do
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      page_id = Ash.Changeset.get_attribute(changeset, :page_id)
      locale = Ash.Changeset.get_attribute(changeset, :locale)

      next_version = get_next_version(page_id, locale)

      changeset
      |> Ash.Changeset.force_change_attribute(:version_number, next_version)
      |> Ash.Changeset.force_change_attribute(:is_current, true)
    end)
  end

  defp get_next_version(page_id, locale) do
    import Ecto.Query

    page_id_bin = Ecto.UUID.dump!(page_id)

    # Advisory lock prevents concurrent inserts from reading the same max version.
    # The lock is scoped to this transaction and released on commit/rollback.
    lock_key = :erlang.phash2({page_id, locale})
    Nexus.Repo.query!("SELECT pg_advisory_xact_lock($1)", [lock_key])

    query =
      from v in "page_versions",
        where: v.page_id == ^page_id_bin and v.locale == ^locale,
        select: max(v.version_number)

    case Nexus.Repo.one(query) do
      nil -> 1
      max -> max + 1
    end
  end
end
