defmodule Nexus.Checks.MembershipLookup do
  @moduledoc """
  Shared helper for checking whether a user has a given role on a project.
  Used by policy checks that need fast, low-level membership lookups.
  """
  import Ecto.Query

  def has_role?(user_id, project_id, roles) do
    user_id_bin = Ecto.UUID.dump!(user_id)
    project_id_bin = Ecto.UUID.dump!(project_id)
    role_strings = Enum.map(roles, &to_string/1)

    from(m in "memberships",
      where:
        m.user_id == ^user_id_bin and m.project_id == ^project_id_bin and
          m.role in ^role_strings,
      select: count()
    )
    |> Nexus.Repo.one() > 0
  end

  def project_id_for_page(page_id) do
    page_id_bin = Ecto.UUID.dump!(page_id)

    case Nexus.Repo.one(
           from(p in "pages",
             where: p.id == ^page_id_bin,
             select: p.project_id
           )
         ) do
      nil -> nil
      bin when is_binary(bin) -> Ecto.UUID.cast!(bin)
    end
  end
end
