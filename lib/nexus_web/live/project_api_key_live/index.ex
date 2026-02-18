defmodule NexusWeb.ProjectApiKeyLive.Index do
  use NexusWeb, :live_view

  on_mount {NexusWeb.LiveUserAuth, :live_user_required}
  on_mount {NexusWeb.ProjectScope, :default}

  @scopes [
    {"Pages Read", :pages_read},
    {"Pages Write", :pages_write},
    {"Pages Update", :pages_update},
    {"Pages Delete", :pages_delete},
    {"Pages Publish", :pages_publish},
    {"Folders Read", :folders_read},
    {"Folders Write", :folders_write},
    {"Full Access", :full_access}
  ]

  @impl true
  def mount(_params, _session, socket) do
    project = socket.assigns.project
    api_keys = list_api_keys(project, socket.assigns.current_user)

    {:ok,
     socket
     |> assign(:page_title, "#{project.name} - API Keys")
     |> assign(:scopes, @scopes)
     |> assign(:new_key_raw, nil)
     |> assign(:show_create, false)
     |> stream(:api_keys, api_keys)}
  end

  @impl true
  def handle_event("toggle_create", _params, socket) do
    {:noreply, assign(socket, :show_create, !socket.assigns.show_create)}
  end

  @impl true
  def handle_event("create_key", %{"name" => name, "scopes" => scopes}, socket) do
    scope_atoms = Enum.map(scopes, &String.to_existing_atom/1)

    case Nexus.Projects.ProjectApiKey.create(
           %{
             name: name,
             scopes: scope_atoms,
             project_id: socket.assigns.project.id,
             created_by_id: socket.assigns.current_user.id
           },
           actor: socket.assigns.current_user
         ) do
      {:ok, api_key} ->
        raw_key = api_key.__metadata__.raw_key

        {:noreply,
         socket
         |> stream_insert(:api_keys, api_key, at: 0)
         |> assign(:new_key_raw, raw_key)
         |> assign(:show_create, false)
         |> put_flash(:info, "API key created")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to create API key")}
    end
  end

  @impl true
  def handle_event("create_key", %{"name" => name}, socket) do
    handle_event("create_key", %{"name" => name, "scopes" => ["pages_read"]}, socket)
  end

  @impl true
  def handle_event("dismiss_key", _params, socket) do
    {:noreply, assign(socket, :new_key_raw, nil)}
  end

  @impl true
  def handle_event("revoke_key", %{"id" => id}, socket) do
    case Ash.get(Nexus.Projects.ProjectApiKey, id, authorize?: false) do
      {:ok, api_key} ->
        case Ash.update(api_key, %{}, action: :revoke, actor: socket.assigns.current_user) do
          {:ok, updated} ->
            {:noreply,
             socket
             |> stream_insert(:api_keys, updated)
             |> put_flash(:info, "API key revoked")}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Failed to revoke key")}
        end

      _ ->
        {:noreply, put_flash(socket, :error, "Key not found")}
    end
  end

  @impl true
  def handle_event(event, params, socket)
      when event in ~w(reorder_tree_item start_creating_page start_creating_folder cancel_inline_create save_inline_content) do
    NexusWeb.ContentTreeHandlers.handle_event(event, params, socket)
  end

  defp list_api_keys(project, user) do
    require Ash.Query

    Nexus.Projects.ProjectApiKey
    |> Ash.Query.for_read(:read, %{}, actor: user)
    |> Ash.Query.filter(project_id == ^project.id)
    |> Ash.read!()
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
      creating_content_type={@creating_content_type}
      breadcrumbs={[{"API Keys", nil}]}
    >
      <div class="p-6">
        <div class="flex items-center justify-between mb-8">
          <h1 class="text-2xl font-bold">API Keys</h1>
          <.button
            :if={@project_role == :admin}
            phx-click="toggle_create"
            class="btn btn-primary btn-sm"
          >
            <.icon name="hero-plus" class="size-4" /> New Key
          </.button>
        </div>

        <div :if={@new_key_raw} class="alert alert-info mb-6">
          <.icon name="hero-key" class="size-5" />
          <div>
            <p class="font-semibold">Save this key now - it won't be shown again:</p>
            <code class="block mt-1 text-sm font-mono break-all">{@new_key_raw}</code>
          </div>
          <.button phx-click="dismiss_key" class="btn btn-sm btn-ghost">Dismiss</.button>
        </div>

        <div :if={@show_create} class="card bg-base-200 mb-6">
          <div class="card-body">
            <h3 class="card-title text-base">Create API Key</h3>
            <.form for={%{}} id="create-api-key-form" phx-submit="create_key" class="space-y-4">
              <.input name="name" label="Name" value="" required />
              <fieldset>
                <legend class="label">Scopes</legend>
                <div class="grid grid-cols-2 gap-2 mt-1">
                  <label
                    :for={{label, value} <- @scopes}
                    class="flex items-center gap-2 cursor-pointer"
                  >
                    <input
                      type="checkbox"
                      name="scopes[]"
                      value={value}
                      checked={value == :pages_read}
                      class="checkbox checkbox-sm"
                    />
                    <span class="text-sm">{label}</span>
                  </label>
                </div>
              </fieldset>
              <div class="flex justify-end gap-2">
                <.button type="button" phx-click="toggle_create" class="btn btn-ghost btn-sm">
                  Cancel
                </.button>
                <.button type="submit" class="btn btn-primary btn-sm">Create</.button>
              </div>
            </.form>
          </div>
        </div>

        <div id="api-keys" phx-update="stream" class="space-y-2">
          <div class="hidden only:block text-center py-8 text-base-content/60">
            No API keys yet.
          </div>
          <div
            :for={{id, key} <- @streams.api_keys}
            id={id}
            class={[
              "flex items-center justify-between p-4 bg-base-200 rounded-box",
              !key.is_active && "opacity-50"
            ]}
          >
            <div>
              <div class="font-medium">{key.name}</div>
              <div class="text-sm text-base-content/60">
                <span class="font-mono">{key.key_prefix}...</span>
                <span class="ml-2">
                  {Enum.map_join(key.scopes, ", ", &to_string/1)}
                </span>
              </div>
            </div>
            <div class="flex items-center gap-2">
              <span :if={!key.is_active} class="badge badge-error badge-sm">Revoked</span>
              <.button
                :if={key.is_active && @project_role == :admin}
                phx-click="revoke_key"
                phx-value-id={key.id}
                class="btn btn-ghost btn-sm text-error"
                data-confirm="Revoke this API key?"
              >
                Revoke
              </.button>
            </div>
          </div>
        </div>
      </div>
    </Layouts.project>
    """
  end
end
