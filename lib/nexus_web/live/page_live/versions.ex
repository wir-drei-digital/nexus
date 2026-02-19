defmodule NexusWeb.PageLive.Versions do
  use NexusWeb, :live_view

  on_mount {NexusWeb.LiveUserAuth, :live_user_required}
  on_mount {NexusWeb.ProjectScope, :default}

  @impl true
  def mount(%{"id" => page_id}, _session, socket) do
    user = socket.assigns.current_user
    project = socket.assigns.project

    case Ash.get(Nexus.Content.Page, page_id, actor: user) do
      {:ok, page} ->
        locale = project.default_locale
        versions = load_versions(page, locale)

        {:ok,
         socket
         |> assign(:page_title, "#{page.slug} - Version History")
         |> assign(:page, page)
         |> assign(:current_locale, locale)
         |> stream(:versions, versions)}

      {:error, _} ->
        {:ok,
         socket
         |> put_flash(:error, "Page not found")
         |> push_navigate(to: ~p"/admin/#{project.slug}")}
    end
  end

  @impl true
  def handle_event("switch_locale", %{"locale" => locale}, socket) do
    versions = load_versions(socket.assigns.page, locale)

    {:noreply,
     socket
     |> assign(:current_locale, locale)
     |> stream(:versions, versions, reset: true)}
  end

  @impl true
  def handle_event("rollback", %{"id" => version_id}, socket) do
    user = socket.assigns.current_user

    case Nexus.Content.PageVersion.rollback(version_id,
           actor: user,
           context: %{created_by_id: user.id}
         ) do
      {:ok, new_version} ->
        versions = load_versions(socket.assigns.page, socket.assigns.current_locale)

        {:noreply,
         socket
         |> stream(:versions, versions, reset: true)
         |> put_flash(:info, "Rolled back to create version #{new_version.version_number}")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to rollback")}
    end
  end

  @impl true
  def handle_event(event, params, socket)
      when event in ~w(reorder_tree_item start_creating_page start_creating_folder cancel_inline_create save_inline_content) do
    NexusWeb.ContentTreeHandlers.handle_event(event, params, socket)
  end

  defp load_versions(page, locale) do
    Nexus.Content.PageVersion.history!(page.id, locale, authorize?: false)
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
      active_path={to_string(@page.full_path)}
      breadcrumbs={[
        {to_string(@page.slug), ~p"/admin/#{@project.slug}/pages/#{@page.id}/edit"},
        {"Versions", nil}
      ]}
    >
      <div class="p-6">
        <div class="flex items-center justify-between mb-6">
          <div>
            <h1 class="text-2xl font-bold">Version History</h1>
            <p class="text-sm text-base-content/60 mt-1">
              <span class="font-mono">{@page.full_path}</span>
              <span class="mx-2 text-base-content/30">|</span>
              Locale: <span class="font-semibold">{@current_locale}</span>
            </p>
          </div>
          <.link
            navigate={~p"/admin/#{@project.slug}/pages/#{@page.id}/edit"}
            class="btn btn-ghost btn-sm"
          >
            <.icon name="hero-pencil" class="size-4" /> Back to Editor
          </.link>
        </div>

        <div id="versions" phx-update="stream" class="space-y-3">
          <div class="hidden only:block text-center py-8 text-base-content/60">
            No versions yet for this locale.
          </div>
          <div
            :for={{id, version} <- @streams.versions}
            id={id}
            class={[
              "flex items-center justify-between p-4 rounded-box",
              if(version.is_current,
                do: "bg-primary/10 border border-primary/30",
                else: "bg-base-200"
              )
            ]}
          >
            <div>
              <div class="flex items-center gap-2">
                <span class="font-bold">v{version.version_number}</span>
                <span :if={version.is_current} class="badge badge-primary badge-sm">Current</span>
              </div>
              <div class="text-sm text-base-content/60">
                {version.title || "(untitled)"}
              </div>
              <div class="text-xs text-base-content/40">
                {Calendar.strftime(version.inserted_at, "%Y-%m-%d %H:%M:%S")} | {map_size(
                  version.template_data || %{}
                )} sections
              </div>
            </div>
            <button
              :if={!version.is_current}
              phx-click="rollback"
              phx-value-id={version.id}
              class="btn btn-ghost btn-sm"
              data-confirm={"Rollback to version #{version.version_number}? This creates a new version with the old content."}
            >
              <.icon name="hero-arrow-uturn-left" class="size-4" /> Rollback
            </button>
          </div>
        </div>
      </div>
    </Layouts.project>
    """
  end
end
