defmodule NexusWeb.PageLive.New do
  use NexusWeb, :live_view

  on_mount {NexusWeb.LiveUserAuth, :live_user_required}
  on_mount {NexusWeb.ProjectScope, :default}

  alias Nexus.Content.Templates.Registry

  @impl true
  def mount(_params, _session, socket) do
    project = socket.assigns.project
    folders = list_folders(project, socket.assigns.current_user)
    available_templates = Registry.available_for_project(project.available_templates)

    form =
      to_form(%{
        "slug" => "",
        "folder_id" => "",
        "parent_page_id" => "",
        "template_slug" => "default"
      })

    {:ok,
     socket
     |> assign(:page_title, "#{project.name} - New Page")
     |> assign(:folders, folders)
     |> assign(:available_templates, available_templates)
     |> assign(:form, form)}
  end

  @impl true
  def handle_event("save", params, socket) do
    attrs =
      params
      |> Map.put("project_id", socket.assigns.project.id)
      |> clean_optional("folder_id")
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
  def handle_event(event, params, socket)
      when event in ~w(reorder_tree_item start_creating_page start_creating_folder cancel_inline_create save_inline_content) do
    NexusWeb.ContentTreeHandlers.handle_event(event, params, socket)
  end

  defp clean_optional(params, key) do
    case Map.get(params, key) do
      "" -> Map.delete(params, key)
      nil -> Map.delete(params, key)
      _ -> params
    end
  end

  defp list_folders(project, user) do
    Nexus.Content.Folder.for_project!(project.id, actor: user)
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
      breadcrumbs={[{"New Page", nil}]}
    >
      <div class="p-6 max-w-xl">
        <h1 class="text-2xl font-bold mb-8">New Page</h1>

        <.form for={@form} id="new-page-form" phx-submit="save" class="space-y-4">
          <.input field={@form[:slug]} label="Slug" name="slug" required />
          <.input
            type="select"
            name="folder_id"
            label="Folder (optional)"
            prompt="None (root)"
            options={Enum.map(@folders, &{&1.full_path, &1.id})}
            value=""
          />
          <.input
            field={@form[:parent_page_id]}
            label="Parent Page ID (optional)"
            name="parent_page_id"
          />
          <.input
            :if={length(@available_templates) > 1}
            type="select"
            name="template_slug"
            label="Template"
            options={Enum.map(@available_templates, &{&1.label, &1.slug})}
            value="default"
          />
          <div class="flex justify-end gap-2 mt-6">
            <.link navigate={~p"/projects/#{@project.slug}"} class="btn btn-ghost">
              Cancel
            </.link>
            <.button type="submit" class="btn btn-primary">Create Page</.button>
          </div>
        </.form>
      </div>
    </Layouts.project>
    """
  end
end
