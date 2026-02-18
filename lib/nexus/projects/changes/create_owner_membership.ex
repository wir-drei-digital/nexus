defmodule Nexus.Projects.Changes.CreateOwnerMembership do
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, context) do
    Ash.Changeset.after_action(changeset, fn _changeset, project ->
      Nexus.Projects.Membership
      |> Ash.Changeset.for_create(:create, %{
        project_id: project.id,
        user_id: context.actor.id,
        role: :admin
      })
      |> Ash.create!(authorize?: false)

      {:ok, project}
    end)
  end
end
