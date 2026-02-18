defmodule NexusWeb.ProjectLive.Show do
  use NexusWeb, :live_view

  on_mount {NexusWeb.LiveUserAuth, :live_user_required}
  on_mount {NexusWeb.ProjectScope, :default}

  @impl true
  def mount(_params, _session, socket) do
    project = socket.assigns.project
    user = socket.assigns.current_user

    project = Ash.load!(project, [:page_count, :directory_count], actor: user)

    {:ok,
     socket
     |> assign(:page_title, project.name)
     |> assign(:project, project)}
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
    >
      <div class="p-6">
        <div class="flex items-center justify-between mb-8">
          <div>
            <h1 class="text-2xl font-bold">{@project.name}</h1>
            <p :if={@project.description} class="text-base-content/60 mt-1">
              {@project.description}
            </p>
          </div>
        </div>

        <div class="grid gap-4 sm:grid-cols-2 lg:grid-cols-4 mb-8">
          <div class="stat bg-base-200 rounded-box">
            <div class="stat-title">Pages</div>
            <div class="stat-value text-2xl">{@project.page_count}</div>
          </div>
          <div class="stat bg-base-200 rounded-box">
            <div class="stat-title">Directories</div>
            <div class="stat-value text-2xl">{@project.directory_count}</div>
          </div>
          <div class="stat bg-base-200 rounded-box">
            <div class="stat-title">Default Locale</div>
            <div class="stat-value text-2xl">{@project.default_locale}</div>
          </div>
          <div class="stat bg-base-200 rounded-box">
            <div class="stat-title">Visibility</div>
            <div class="stat-value text-2xl">
              {if @project.is_public, do: "Public", else: "Private"}
            </div>
          </div>
        </div>

        <div class="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
          <.link
            navigate={~p"/projects/#{@project.slug}/pages"}
            class="card bg-base-200 hover:bg-base-300 transition-colors"
          >
            <div class="card-body">
              <h3 class="card-title text-base">
                <.icon name="hero-document-text" class="size-5" /> Pages
              </h3>
              <p class="text-sm text-base-content/60">Manage content pages</p>
            </div>
          </.link>
          <.link
            navigate={~p"/projects/#{@project.slug}/directories"}
            class="card bg-base-200 hover:bg-base-300 transition-colors"
          >
            <div class="card-body">
              <h3 class="card-title text-base">
                <.icon name="hero-folder" class="size-5" /> Directories
              </h3>
              <p class="text-sm text-base-content/60">Organize content structure</p>
            </div>
          </.link>
          <.link
            navigate={~p"/projects/#{@project.slug}/members"}
            class="card bg-base-200 hover:bg-base-300 transition-colors"
          >
            <div class="card-body">
              <h3 class="card-title text-base">
                <.icon name="hero-users" class="size-5" /> Members
              </h3>
              <p class="text-sm text-base-content/60">Manage team access</p>
            </div>
          </.link>
        </div>
      </div>
    </Layouts.project>
    """
  end
end
