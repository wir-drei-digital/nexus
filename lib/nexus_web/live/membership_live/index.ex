defmodule NexusWeb.MembershipLive.Index do
  use NexusWeb, :live_view

  on_mount {NexusWeb.LiveUserAuth, :live_user_required}
  on_mount {NexusWeb.ProjectScope, :default}

  @impl true
  def mount(_params, _session, socket) do
    project = socket.assigns.project
    user = socket.assigns.current_user
    memberships = list_memberships(project, user)
    member_ids = MapSet.new(memberships, & &1.user_id)
    all_users = Ash.read!(Nexus.Accounts.User, actor: user)
    non_members = Enum.reject(all_users, &MapSet.member?(member_ids, &1.id))

    {:ok,
     socket
     |> assign(:page_title, "#{project.name} - Members")
     |> stream(:memberships, memberships)
     |> assign(:non_members, non_members)}
  end

  @impl true
  def handle_event("update_role", %{"membership_id" => id, "role" => role}, socket) do
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
  def handle_event("add_member", %{"user_id" => user_id, "role" => role}, socket) do
    project = socket.assigns.project
    role_atom = String.to_existing_atom(role)

    case Nexus.Projects.Membership.create(
           %{user_id: user_id, project_id: project.id, role: role_atom},
           actor: socket.assigns.current_user
         ) do
      {:ok, membership} ->
        membership = Ash.load!(membership, [:user], authorize?: false)
        non_members = Enum.reject(socket.assigns.non_members, &(&1.id == user_id))

        {:noreply,
         socket
         |> stream_insert(:memberships, membership)
         |> assign(:non_members, non_members)
         |> put_flash(:info, "Member added")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to add member")}
    end
  end

  @impl true
  def handle_event("remove_member", %{"id" => id}, socket) do
    case Ash.get(Nexus.Projects.Membership, id, authorize?: false) do
      {:ok, membership} ->
        case Ash.destroy(membership, actor: socket.assigns.current_user) do
          :ok ->
            removed_user = Ash.get!(Nexus.Accounts.User, membership.user_id, authorize?: false)

            {:noreply,
             socket
             |> stream_delete(:memberships, membership)
             |> assign(:non_members, [removed_user | socket.assigns.non_members])
             |> put_flash(:info, "Member removed")}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Failed to remove member")}
        end

      _ ->
        {:noreply, put_flash(socket, :error, "Member not found")}
    end
  end

  @impl true
  def handle_event(event, params, socket)
      when event in ~w(reorder_tree_item start_creating_page start_creating_folder cancel_inline_create save_inline_content) do
    NexusWeb.ContentTreeHandlers.handle_event(event, params, socket)
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
      sidebar_folders={@sidebar_folders}
      sidebar_pages={@sidebar_pages}
      page_titles={@page_titles}
      creating_content_type={@creating_content_type}
      breadcrumbs={[{"Members", nil}]}
    >
      <div class="p-6">
        <h1 class="text-2xl font-bold mb-6">Team Members</h1>

        <div id="memberships" phx-update="stream" class="space-y-2 mb-10">
          <div class="hidden only:block text-center py-8 text-base-content/60">
            No members found.
          </div>
          <div
            :for={{id, membership} <- @streams.memberships}
            id={id}
            class="flex items-center justify-between p-4 bg-base-200 rounded-box"
          >
            <div class="flex items-center gap-3">
              <div class="flex items-center justify-center w-10 h-10 rounded-full bg-neutral text-neutral-content shrink-0">
                <span class="text-sm font-medium leading-none">
                  {membership.user.email |> to_string() |> String.first() |> String.upcase()}
                </span>
              </div>
              <div>
                <div class="font-medium">
                  {membership.user.email}
                  <span
                    :if={membership.user_id == @current_user.id}
                    class="badge badge-sm badge-ghost ml-1"
                  >
                    You
                  </span>
                </div>
                <div class="text-sm text-base-content/60 capitalize">{membership.role}</div>
              </div>
            </div>

            <div
              :if={@project_role == :admin and membership.user_id != @current_user.id}
              class="flex items-center gap-2"
            >
              <form phx-change="update_role">
                <input type="hidden" name="membership_id" value={membership.id} />
                <select class="select select-sm select-bordered" name="role">
                  <option value="admin" selected={membership.role == :admin}>Admin</option>
                  <option value="editor" selected={membership.role == :editor}>Editor</option>
                  <option value="viewer" selected={membership.role == :viewer}>Viewer</option>
                </select>
              </form>
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

        <div :if={@project_role == :admin and @non_members != []}>
          <h2 class="text-lg font-semibold mb-4">Add Users</h2>
          <div class="space-y-2">
            <div
              :for={user <- @non_members}
              class="flex items-center justify-between p-4 bg-base-200 rounded-box"
            >
              <div class="flex items-center gap-3">
                <div class="flex items-center justify-center w-10 h-10 rounded-full bg-base-300 text-base-content shrink-0">
                  <span class="text-sm font-medium leading-none">
                    {user.email |> to_string() |> String.first() |> String.upcase()}
                  </span>
                </div>
                <div class="font-medium">{user.email}</div>
              </div>
              <form phx-submit="add_member" class="flex items-center gap-2">
                <input type="hidden" name="user_id" value={user.id} />
                <select class="select select-sm select-bordered" name="role">
                  <option value="viewer">Viewer</option>
                  <option value="editor">Editor</option>
                  <option value="admin">Admin</option>
                </select>
                <button type="submit" class="btn btn-sm btn-primary">Add</button>
              </form>
            </div>
          </div>
        </div>
      </div>
    </Layouts.project>
    """
  end
end
