defmodule NexusWeb.ProjectLive.Show do
  use NexusWeb, :live_view

  on_mount {NexusWeb.LiveUserAuth, :live_user_required}
  on_mount {NexusWeb.ProjectScope, :default}

  @impl true
  def mount(_params, _session, socket) do
    project = socket.assigns.project
    user = socket.assigns.current_user

    project = Ash.load!(project, [:page_count, :folder_count], actor: user)

    {:ok,
     socket
     |> assign(:page_title, project.name)
     |> assign(:project, project)}
  end

  @impl true
  def handle_event(event, params, socket)
      when event in ~w(reorder_tree_item start_creating_page start_creating_folder cancel_inline_create save_inline_content) do
    NexusWeb.ContentTreeHandlers.handle_event(event, params, socket)
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
            <div class="stat-title">Folders</div>
            <div class="stat-value text-2xl">{@project.folder_count}</div>
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
