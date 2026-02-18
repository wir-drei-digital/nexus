defmodule NexusWeb.ProjectLive.Index do
  use NexusWeb, :live_view

  on_mount {NexusWeb.LiveUserAuth, :live_user_required}

  @impl true
  def mount(_params, _session, socket) do
    projects = list_projects(socket.assigns.current_user)

    {:ok,
     socket
     |> assign(:page_title, "Projects")
     |> stream(:projects, projects)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, _params) do
    assign(socket, :form, to_form(project_changeset()))
  end

  defp apply_action(socket, _action, _params) do
    socket
  end

  @impl true
  def handle_event("save_project", %{"form" => params}, socket) do
    case Nexus.Projects.Project.create(params, actor: socket.assigns.current_user) do
      {:ok, project} ->
        {:noreply,
         socket
         |> put_flash(:info, "Project created successfully")
         |> push_navigate(to: ~p"/projects/#{project.slug}")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  defp list_projects(user) do
    Nexus.Projects.Project
    |> Ash.Query.for_read(:read, %{}, actor: user)
    |> Ash.read!()
  end

  defp project_changeset do
    AshPhoenix.Form.for_create(Nexus.Projects.Project, :create)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="flex items-center justify-between mb-8">
        <h1 class="text-2xl font-bold">Projects</h1>
        <.link patch={~p"/projects/new"} class="btn btn-primary btn-sm">
          <.icon name="hero-plus" class="size-4" /> New Project
        </.link>
      </div>

      <div id="projects" phx-update="stream" class="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
        <div class="hidden only:block text-center py-12 text-base-content/60">
          No projects yet. Create your first project to get started.
        </div>
        <.link
          :for={{id, project} <- @streams.projects}
          id={id}
          navigate={~p"/projects/#{project.slug}"}
          class="card bg-base-200 hover:bg-base-300 transition-colors cursor-pointer"
        >
          <div class="card-body">
            <h2 class="card-title text-lg">{project.name}</h2>
            <p :if={project.description} class="text-sm text-base-content/60 line-clamp-2">
              {project.description}
            </p>
            <div class="flex gap-2 mt-2">
              <span class="badge badge-sm badge-ghost">{project.default_locale}</span>
              <span :if={project.is_public} class="badge badge-sm badge-info">Public</span>
            </div>
          </div>
        </.link>
      </div>

      <div
        :if={@live_action == :new}
        id="new-project-modal"
        class="fixed inset-0 z-50 flex items-center justify-center bg-black/50"
      >
        <div
          class="card bg-base-100 w-full max-w-md shadow-xl"
          phx-click-away={JS.patch(~p"/projects")}
        >
          <div class="card-body">
            <h2 class="card-title mb-4">New Project</h2>
            <.form for={@form} id="new-project-form" phx-submit="save_project" class="space-y-4">
              <.input field={@form[:name]} label="Name" required />
              <.input field={@form[:slug]} label="Slug" required />
              <.input field={@form[:description]} label="Description" type="textarea" />
              <.input field={@form[:default_locale]} label="Default Locale" value="en" />
              <.input field={@form[:is_public]} label="Public" type="checkbox" />
              <div class="flex justify-end gap-2 mt-6">
                <.link patch={~p"/projects"} class="btn btn-ghost">Cancel</.link>
                <button type="submit" class="btn btn-primary">Create Project</button>
              </div>
            </.form>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
