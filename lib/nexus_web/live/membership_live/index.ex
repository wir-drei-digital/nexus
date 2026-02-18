defmodule NexusWeb.MembershipLive.Index do
  use NexusWeb, :live_view

  on_mount {NexusWeb.LiveUserAuth, :live_user_required}
  on_mount {NexusWeb.ProjectScope, :default}

  @impl true
  def mount(_params, _session, socket) do
    project = socket.assigns.project
    memberships = list_memberships(project, socket.assigns.current_user)

    {:ok,
     socket
     |> assign(:page_title, "#{project.name} - Members")
     |> stream(:memberships, memberships)
     |> assign(:invite_form, to_form(%{"email" => "", "role" => "viewer"}))}
  end

  @impl true
  def handle_event("update_role", %{"id" => id, "role" => role}, socket) do
    role_atom = String.to_existing_atom(role)

    case Ash.get(Nexus.Projects.Membership, id, authorize?: false) do
      {:ok, membership} ->
        case Ash.update(membership, %{role: role_atom},
               action: :update_role,
               actor: socket.assigns.current_user
             ) do
          {:ok, updated} ->
            updated = Ash.load!(updated, [:user], authorize?: false)

            {:noreply,
             socket
             |> stream_insert(:memberships, updated)
             |> put_flash(:info, "Role updated")}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Failed to update role")}
        end

      _ ->
        {:noreply, put_flash(socket, :error, "Member not found")}
    end
  end

  @impl true
  def handle_event("remove_member", %{"id" => id}, socket) do
    case Ash.get(Nexus.Projects.Membership, id, authorize?: false) do
      {:ok, membership} ->
        case Ash.destroy(membership, actor: socket.assigns.current_user) do
          :ok ->
            {:noreply,
             socket
             |> stream_delete(:memberships, membership)
             |> put_flash(:info, "Member removed")}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Failed to remove member")}
        end

      _ ->
        {:noreply, put_flash(socket, :error, "Member not found")}
    end
  end

  @impl true
  def handle_event("reorder_tree_item", params, socket) do
    NexusWeb.ContentTreeHandlers.handle_event("reorder_tree_item", params, socket)
  end

  defp list_memberships(project, user) do
    Nexus.Projects.Membership.for_project!(project.id,
      actor: user,
      load: [:user]
    )
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.project
      flash={@flash}
      project={@project}
      project_role={@project_role}
      sidebar_directories={@sidebar_directories}
      sidebar_pages={@sidebar_pages}
      breadcrumbs={[{"Members", nil}]}
    >
      <div class="p-6">
        <h1 class="text-2xl font-bold mb-8">Team Members</h1>

        <div id="memberships" phx-update="stream" class="space-y-2">
          <div class="hidden only:block text-center py-8 text-base-content/60">
            No members found.
          </div>
          <div
            :for={{id, membership} <- @streams.memberships}
            id={id}
            class="flex items-center justify-between p-4 bg-base-200 rounded-box"
          >
            <div class="flex items-center gap-3">
              <div class="avatar placeholder">
                <div class="bg-neutral text-neutral-content w-10 rounded-full">
                  <span class="text-sm">
                    {membership.user.email |> to_string() |> String.first() |> String.upcase()}
                  </span>
                </div>
              </div>
              <div>
                <div class="font-medium">{membership.user.email}</div>
                <div class="text-sm text-base-content/60 capitalize">{membership.role}</div>
              </div>
            </div>

            <div :if={@project_role == :admin} class="flex items-center gap-2">
              <select
                class="select select-sm select-bordered"
                phx-change="update_role"
                phx-value-id={membership.id}
                name="role"
              >
                <option value="admin" selected={membership.role == :admin}>Admin</option>
                <option value="editor" selected={membership.role == :editor}>Editor</option>
                <option value="viewer" selected={membership.role == :viewer}>Viewer</option>
              </select>
              <button
                phx-click="remove_member"
                phx-value-id={membership.id}
                class="btn btn-ghost btn-sm text-error"
                data-confirm="Remove this member?"
              >
                <.icon name="hero-trash" class="size-4" />
              </button>
            </div>
          </div>
        </div>
      </div>
    </Layouts.project>
    """
  end
end
