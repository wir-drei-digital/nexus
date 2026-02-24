defmodule NexusWeb.MediaLive.Index do
  use NexusWeb, :live_view

  on_mount {NexusWeb.LiveUserAuth, :live_user_required}
  on_mount {NexusWeb.ProjectScope, :default}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Media")
     |> assign(:breadcrumbs, [{"Media", nil}])}
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
      breadcrumbs={@breadcrumbs}
    >
      <div class="p-6">
        <h1 class="text-2xl font-bold">Media Library</h1>
        <p class="text-base-content/60 mt-2">Coming soon...</p>
      </div>
    </Layouts.project>
    """
  end
end
