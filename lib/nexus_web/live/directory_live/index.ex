defmodule NexusWeb.DirectoryLive.Index do
  use NexusWeb, :live_view

  on_mount {NexusWeb.LiveUserAuth, :live_user_required}
  on_mount {NexusWeb.ProjectScope, :default}

  @impl true
  def mount(_params, _session, socket) do
    project = socket.assigns.project
    user = socket.assigns.current_user
    directories = list_directories(project, user)

    {:ok,
     socket
     |> assign(:page_title, "#{project.name} - Directories")
     |> assign(:show_form, false)
     |> assign(:editing, nil)
     |> assign(:form, new_create_form(project, user))
     |> stream(:directories, directories)}
  end

  @impl true
  def handle_event("toggle_form", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_form, !socket.assigns.show_form)
     |> assign(:editing, nil)
     |> assign(:form, new_create_form(socket.assigns.project, socket.assigns.current_user))}
  end

  @impl true
  def handle_event("edit", %{"id" => id}, socket) do
    user = socket.assigns.current_user

    case Ash.get(Nexus.Content.Directory, id, authorize?: false) do
      {:ok, dir} ->
        form =
          dir
          |> AshPhoenix.Form.for_update(:update, actor: user)
          |> to_form()

        {:noreply,
         socket
         |> assign(:show_form, true)
         |> assign(:editing, dir)
         |> assign(:form, form)}

      _ ->
        {:noreply, put_flash(socket, :error, "Directory not found")}
    end
  end

  @impl true
  def handle_event("validate", %{"form" => params}, socket) do
    form =
      if socket.assigns.editing do
        AshPhoenix.Form.for_update(socket.assigns.editing, :update,
          params: params,
          actor: socket.assigns.current_user
        )
      else
        AshPhoenix.Form.for_create(Nexus.Content.Directory, :create,
          params: Map.put(params, "project_id", socket.assigns.project.id),
          actor: socket.assigns.current_user
        )
      end
      |> AshPhoenix.Form.validate(params)
      |> to_form()

    {:noreply, assign(socket, :form, form)}
  end

  @impl true
  def handle_event("save", %{"form" => params}, socket) do
    if socket.assigns.editing do
      update_directory(socket, params)
    else
      create_directory(socket, params)
    end
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    case Ash.get(Nexus.Content.Directory, id, authorize?: false) do
      {:ok, dir} ->
        case Ash.destroy(dir, actor: socket.assigns.current_user) do
          :ok ->
            {:noreply,
             socket
             |> stream_delete(:directories, dir)
             |> put_flash(:info, "Directory deleted")}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Failed to delete directory")}
        end

      _ ->
        {:noreply, put_flash(socket, :error, "Directory not found")}
    end
  end

  @impl true
  def handle_event("reorder_tree_item", params, socket) do
    NexusWeb.ContentTreeHandlers.handle_event("reorder_tree_item", params, socket)
  end

  defp create_directory(socket, params) do
    user = socket.assigns.current_user
    project = socket.assigns.project

    form =
      AshPhoenix.Form.for_create(Nexus.Content.Directory, :create,
        params: Map.put(params, "project_id", project.id),
        actor: user
      )

    case AshPhoenix.Form.submit(form) do
      {:ok, dir} ->
        {:noreply,
         socket
         |> stream_insert(:directories, dir)
         |> assign(:show_form, false)
         |> assign(:form, new_create_form(project, user))
         |> put_flash(:info, "Directory created")}

      {:error, form} ->
        {:noreply, assign(socket, :form, to_form(form))}
    end
  end

  defp update_directory(socket, params) do
    user = socket.assigns.current_user

    form =
      AshPhoenix.Form.for_update(socket.assigns.editing, :update,
        params: params,
        actor: user
      )

    case AshPhoenix.Form.submit(form) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> stream_insert(:directories, updated)
         |> assign(:show_form, false)
         |> assign(:editing, nil)
         |> assign(:form, new_create_form(socket.assigns.project, user))
         |> put_flash(:info, "Directory updated")}

      {:error, form} ->
        {:noreply, assign(socket, :form, to_form(form))}
    end
  end

  defp list_directories(project, user) do
    Nexus.Content.Directory.for_project!(project.id, actor: user)
  end

  defp new_create_form(project, user) do
    Nexus.Content.Directory
    |> AshPhoenix.Form.for_create(:create,
      params: %{"project_id" => project.id},
      actor: user
    )
    |> to_form()
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
      breadcrumbs={[{"Directories", nil}]}
    >
      <div class="p-6">
        <div class="flex items-center justify-between mb-8">
          <h1 class="text-2xl font-bold">Directories</h1>
          <button phx-click="toggle_form" class="btn btn-primary btn-sm">
            <.icon name="hero-plus" class="size-4" /> New Directory
          </button>
        </div>

        <div :if={@show_form} class="card bg-base-200 mb-6">
          <div class="card-body">
            <h3 class="card-title text-base">
              {if @editing, do: "Edit Directory", else: "New Directory"}
            </h3>
            <.form
              for={@form}
              id="directory-form"
              phx-change="validate"
              phx-submit="save"
              class="space-y-4"
            >
              <.input field={@form[:name]} label="Name" required />
              <.input field={@form[:slug]} label="Slug" required />
              <.input field={@form[:parent_id]} label="Parent ID (optional)" />
              <div class="flex justify-end gap-2">
                <button type="button" phx-click="toggle_form" class="btn btn-ghost btn-sm">
                  Cancel
                </button>
                <button type="submit" class="btn btn-primary btn-sm">
                  {if @editing, do: "Update", else: "Create"}
                </button>
              </div>
            </.form>
          </div>
        </div>

        <div id="directories" phx-update="stream" class="space-y-2">
          <div class="hidden only:block text-center py-8 text-base-content/60">
            No directories yet.
          </div>
          <div
            :for={{id, dir} <- @streams.directories}
            id={id}
            class="flex items-center justify-between p-4 bg-base-200 rounded-box"
          >
            <div>
              <div class="font-medium flex items-center gap-2">
                <.icon name="hero-folder" class="size-4 text-base-content/60" />
                {dir.name}
              </div>
              <div class="text-sm text-base-content/60 font-mono">{dir.full_path}</div>
            </div>
            <div class="flex items-center gap-2">
              <button phx-click="edit" phx-value-id={dir.id} class="btn btn-ghost btn-sm">
                <.icon name="hero-pencil" class="size-4" />
              </button>
              <button
                phx-click="delete"
                phx-value-id={dir.id}
                class="btn btn-ghost btn-sm text-error"
                data-confirm="Delete this directory?"
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
