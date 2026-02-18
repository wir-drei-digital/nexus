defmodule Nexus.Projects.Checks.HasProjectRole do
  @moduledoc """
  Policy check that verifies the actor has a required role on a project.

  Used for create actions where filter-based policies are not available.
  For read/update/destroy, prefer `expr(exists(...))` filter policies instead.
  """
  use Ash.Policy.SimpleCheck

  @impl true
  def describe(opts) do
    roles = Keyword.get(opts, :roles, [:admin, :editor, :viewer])
    "actor has one of #{inspect(roles)} roles on the project"
  end

  @impl true
  def match?(nil, _context, _opts), do: false

  def match?(actor, %{changeset: %Ash.Changeset{} = changeset}, opts) do
    roles = Keyword.get(opts, :roles, [:admin, :editor, :viewer])
    project_id = resolve_project_id(changeset)

    if project_id do
      Nexus.Checks.MembershipLookup.has_role?(actor.id, project_id, roles)
    else
      false
    end
  end

  # This check is only intended for create actions; reads use filter policies
  def match?(_actor, %{query: %Ash.Query{}}, _opts), do: false

  def match?(_actor, _context, _opts), do: false

  defp resolve_project_id(changeset) do
    Ash.Changeset.get_argument(changeset, :project_id) ||
      Ash.Changeset.get_attribute(changeset, :project_id)
  end
end
