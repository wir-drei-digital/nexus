defmodule NexusWeb.PageLive.New do
  use NexusWeb, :live_view

  on_mount {NexusWeb.LiveUserAuth, :live_user_required}
  on_mount {NexusWeb.ProjectScope, :default}

  @impl true
  def mount(_params, _session, socket) do
    project = socket.assigns.project
    directories = list_directories(project, socket.assigns.current_user)

    form = to_form(%{"slug" => "", "directory_id" => "", "parent_page_id" => ""})

    {:ok,
     socket
     |> assign(:page_title, "#{project.name} - New Page")
     |> assign(:directories, directories)
     |> assign(:form, form)}
  end

  @impl true
  def handle_event("save", params, socket) do
    attrs =
      params
      |> Map.put("project_id", socket.assigns.project.id)
      |> clean_optional("directory_id")
      |> clean_optional("parent_page_id")

    case Nexus.Content.Page.create(attrs, actor: socket.assigns.current_user) do
      {:ok, page} ->
        {:noreply,
         socket
         |> put_flash(:info, "Page created")
         |> push_navigate(to: ~p"/projects/#{socket.assigns.project.slug}/pages/#{page.id}/edit")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to create page")}
    end
  end

  @impl true
  def handle_event("reorder_tree_item", params, socket) do
    NexusWeb.ContentTreeHandlers.handle_event("reorder_tree_item", params, socket)
  end

  defp clean_optional(params, key) do
    case Map.get(params, key) do
      "" -> Map.delete(params, key)
      nil -> Map.delete(params, key)
      _ -> params
    end
  end

  defp list_directories(project, user) do
    Nexus.Content.Directory.for_project!(project.id, actor: user)
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
      breadcrumbs={[{"Pages", ~p"/projects/#{@project.slug}/pages"}, {"New", nil}]}
    >
      <div class="p-6 max-w-xl">
        <h1 class="text-2xl font-bold mb-8">New Page</h1>

        <.form for={@form} id="new-page-form" phx-submit="save" class="space-y-4">
          <.input field={@form[:slug]} label="Slug" name="slug" required />
          <div>
            <label class="label">Directory (optional)</label>
            <select name="directory_id" class="select select-bordered w-full">
              <option value="">None (root)</option>
              <option :for={dir <- @directories} value={dir.id}>
                {dir.full_path}
              </option>
            </select>
          </div>
          <.input
            field={@form[:parent_page_id]}
            label="Parent Page ID (optional)"
            name="parent_page_id"
          />
          <div class="flex justify-end gap-2 mt-6">
            <.link navigate={~p"/projects/#{@project.slug}/pages"} class="btn btn-ghost">
              Cancel
            </.link>
            <button type="submit" class="btn btn-primary">Create Page</button>
          </div>
        </.form>
      </div>
    </Layouts.project>
    """
  end
end
