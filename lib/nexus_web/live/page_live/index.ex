defmodule NexusWeb.PageLive.Index do
  use NexusWeb, :live_view

  on_mount {NexusWeb.LiveUserAuth, :live_user_required}
  on_mount {NexusWeb.ProjectScope, :default}

  @impl true
  def mount(_params, _session, socket) do
    project = socket.assigns.project
    user = socket.assigns.current_user
    pages = list_pages(project, user, :all)

    {:ok,
     socket
     |> assign(:page_title, "#{project.name} - Pages")
     |> assign(:status_filter, :all)
     |> stream(:pages, pages)}
  end

  @impl true
  def handle_event("filter_status", %{"status" => status}, socket) do
    status_atom = if status == "all", do: :all, else: String.to_existing_atom(status)

    pages =
      list_pages(socket.assigns.project, socket.assigns.current_user, status_atom)

    {:noreply,
     socket
     |> assign(:status_filter, status_atom)
     |> stream(:pages, pages, reset: true)}
  end

  @impl true
  def handle_event("reorder_tree_item", params, socket) do
    NexusWeb.ContentTreeHandlers.handle_event("reorder_tree_item", params, socket)
  end

  defp list_pages(project, user, :all) do
    Nexus.Content.Page.list_for_project!(project.id, actor: user)
  end

  defp list_pages(project, user, status) do
    require Ash.Query

    Nexus.Content.Page
    |> Ash.Query.for_read(:list_for_project, %{project_id: project.id}, actor: user)
    |> Ash.Query.filter(status == ^status)
    |> Ash.read!()
  end

  defp status_badge_class(status) do
    case status do
      :published -> "badge-success"
      :draft -> "badge-warning"
      :archived -> "badge-neutral"
      _ -> "badge-ghost"
    end
  end

  defp format_datetime(nil), do: "-"

  defp format_datetime(dt) do
    Calendar.strftime(dt, "%b %d, %Y %H:%M")
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
      breadcrumbs={[{"Pages", nil}]}
    >
      <div class="p-6">
        <div class="flex items-center justify-between mb-6">
          <h1 class="text-2xl font-bold">Pages</h1>
          <.link
            navigate={~p"/projects/#{@project.slug}/pages/new"}
            class="btn btn-primary btn-sm"
          >
            <.icon name="hero-plus" class="size-4" /> Create Page
          </.link>
        </div>

        <%!-- Status filter tabs --%>
        <div class="flex gap-1 mb-6">
          <button
            :for={
              {label, value} <- [
                {"All", :all},
                {"Draft", :draft},
                {"Published", :published},
                {"Archived", :archived}
              ]
            }
            phx-click="filter_status"
            phx-value-status={value}
            class={[
              "btn btn-sm",
              if(@status_filter == value, do: "btn-primary", else: "btn-ghost")
            ]}
          >
            {label}
          </button>
        </div>

        <%!-- Page table --%>
        <div id="pages" phx-update="stream">
          <div class="hidden only:block text-center py-12 text-base-content/60">
            No pages yet. Create your first page to get started.
          </div>
          <table class="table w-full [&:has(tr:only-child)]:hidden">
            <thead>
              <tr class="text-xs text-base-content/50 uppercase">
                <th class="font-medium">Page</th>
                <th class="font-medium w-28">Status</th>
                <th class="font-medium w-44">Last Updated</th>
                <th class="font-medium w-20"></th>
              </tr>
            </thead>
            <tbody>
              <tr
                :for={{id, page} <- @streams.pages}
                id={id}
                class="hover:bg-base-200/50 transition-colors"
              >
                <td>
                  <.link
                    navigate={~p"/projects/#{@project.slug}/pages/#{page.id}/edit"}
                    class="hover:text-primary"
                  >
                    <div class="font-medium">{page.slug}</div>
                    <div class="text-xs text-base-content/40 font-mono">{page.full_path}</div>
                  </.link>
                </td>
                <td>
                  <span class={["badge badge-sm", status_badge_class(page.status)]}>
                    {page.status}
                  </span>
                </td>
                <td class="text-sm text-base-content/60">
                  {format_datetime(page.updated_at)}
                </td>
                <td>
                  <div class="flex gap-1">
                    <.link
                      navigate={~p"/projects/#{@project.slug}/pages/#{page.id}/edit"}
                      class="btn btn-ghost btn-xs"
                    >
                      <.icon name="hero-pencil" class="size-3.5" />
                    </.link>
                    <.link
                      navigate={~p"/projects/#{@project.slug}/pages/#{page.id}/versions"}
                      class="btn btn-ghost btn-xs"
                    >
                      <.icon name="hero-clock" class="size-3.5" />
                    </.link>
                  </div>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </Layouts.project>
    """
  end
end
