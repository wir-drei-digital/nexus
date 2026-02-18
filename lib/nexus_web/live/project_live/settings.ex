defmodule NexusWeb.ProjectLive.Settings do
  use NexusWeb, :live_view

  on_mount {NexusWeb.LiveUserAuth, :live_user_required}
  on_mount {NexusWeb.ProjectScope, :default}

  @impl true
  def mount(_params, _session, socket) do
    project = socket.assigns.project
    user = socket.assigns.current_user

    form =
      project
      |> AshPhoenix.Form.for_update(:update, actor: user)
      |> to_form()

    {:ok,
     socket
     |> assign(:page_title, "#{project.name} - Settings")
     |> assign(:form, form)}
  end

  @impl true
  def handle_event("validate", %{"form" => params}, socket) do
    form =
      socket.assigns.project
      |> AshPhoenix.Form.for_update(:update,
        params: params,
        actor: socket.assigns.current_user
      )
      |> AshPhoenix.Form.validate(params)
      |> to_form()

    {:noreply, assign(socket, :form, form)}
  end

  @impl true
  def handle_event("save", %{"form" => params}, socket) do
    case AshPhoenix.Form.for_update(socket.assigns.project, :update,
           params: params,
           actor: socket.assigns.current_user
         )
         |> AshPhoenix.Form.submit() do
      {:ok, project} ->
        {:noreply,
         socket
         |> assign(:project, project)
         |> put_flash(:info, "Project updated successfully")}

      {:error, form} ->
        {:noreply, assign(socket, :form, to_form(form))}
    end
  end

  @impl true
  def handle_event("reorder_tree_item", params, socket) do
    NexusWeb.ContentTreeHandlers.handle_event("reorder_tree_item", params, socket)
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
      breadcrumbs={[{"Settings", nil}]}
    >
      <div class="p-6 max-w-xl">
        <h1 class="text-2xl font-bold mb-8">Project Settings</h1>

        <.form
          for={@form}
          id="project-settings-form"
          phx-change="validate"
          phx-submit="save"
          class="space-y-4"
        >
          <.input field={@form[:name]} label="Name" required />
          <.input field={@form[:description]} label="Description" type="textarea" />
          <.input field={@form[:default_locale]} label="Default Locale" required />
          <.input field={@form[:is_public]} label="Public" type="checkbox" />
          <div class="flex justify-end mt-6">
            <button type="submit" class="btn btn-primary" phx-disable-with="Saving...">
              Save Changes
            </button>
          </div>
        </.form>
      </div>
    </Layouts.project>
    """
  end
end
