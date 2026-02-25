defmodule Nexus.Checks.ActorIsProjectAdmin do
  @moduledoc """
  Custom policy check that verifies the actor is an admin of the project
  referenced in the changeset/query. Works for create actions where
  relationship-based expressions cannot be used.
  """
  use Ash.Policy.SimpleCheck

  @impl true
  def describe(_opts), do: "actor is an admin of the target project"

  @impl true
  def match?(nil, _context, _opts), do: false

  def match?(actor, %{changeset: %Ash.Changeset{} = changeset}, _opts) do
    project_id = Ash.Changeset.get_attribute(changeset, :project_id)
    project_id != nil and Nexus.Checks.MembershipLookup.has_role?(actor.id, project_id, [:admin])
  end

  def match?(_actor, _context, _opts), do: false
end
