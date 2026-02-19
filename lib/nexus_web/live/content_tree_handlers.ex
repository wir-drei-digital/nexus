defmodule NexusWeb.ContentTreeHandlers do
  @moduledoc """
  Shared event handlers for content tree drag-and-drop and inline creation operations.
  Import this module's handle_event/3 into LiveViews that use the project layout.
  """
  import Phoenix.LiveView
  import Phoenix.Component, only: [assign: 3]

  def handle_event("start_creating_page", _params, socket) do
    {:noreply, assign(socket, :creating_content_type, :page)}
  end

  def handle_event("start_creating_folder", _params, socket) do
    {:noreply, assign(socket, :creating_content_type, :folder)}
  end

  def handle_event("cancel_inline_create", _params, socket) do
    {:noreply, assign(socket, :creating_content_type, nil)}
  end

  def handle_event("save_inline_content", %{"type" => "page", "name" => name}, socket)
      when name != "" do
    attrs = %{
      "slug" => name,
      "project_id" => socket.assigns.project.id
    }

    case Nexus.Content.Page.create(attrs, actor: socket.assigns.current_user) do
      {:ok, page} ->
        {folders, pages} =
          load_sidebar_data(socket.assigns.project.id, socket.assigns.current_user)

        {:noreply,
         socket
         |> assign(:creating_content_type, nil)
         |> assign(:sidebar_folders, folders)
         |> assign(:sidebar_pages, pages)
         |> push_navigate(to: "/admin/#{socket.assigns.project.slug}/pages/#{page.id}/edit")}

      {:error, _} ->
        {:noreply,
         socket
         |> assign(:creating_content_type, nil)
         |> put_flash(:error, "Failed to create page")}
    end
  end

  def handle_event("save_inline_content", %{"type" => "folder", "name" => name}, socket)
      when name != "" do
    attrs = %{
      "name" => name,
      "slug" => Slug.slugify(name),
      "project_id" => socket.assigns.project.id
    }

    case Nexus.Content.Folder.create(attrs, actor: socket.assigns.current_user) do
      {:ok, _folder} ->
        {folders, pages} =
          load_sidebar_data(socket.assigns.project.id, socket.assigns.current_user)

        {:noreply,
         socket
         |> assign(:creating_content_type, nil)
         |> assign(:sidebar_folders, folders)
         |> assign(:sidebar_pages, pages)
         |> put_flash(:info, "Folder created")}

      {:error, _} ->
        {:noreply,
         socket
         |> assign(:creating_content_type, nil)
         |> put_flash(:error, "Failed to create folder")}
    end
  end

  def handle_event("save_inline_content", _params, socket) do
    {:noreply, assign(socket, :creating_content_type, nil)}
  end

  def handle_event("reorder_tree_item", params, socket) do
    %{
      "item_type" => item_type,
      "item_id" => item_id,
      "new_parent_type" => parent_type,
      "new_parent_id" => parent_id,
      "siblings" => siblings
    } = params

    user = socket.assigns.current_user
    project = socket.assigns.project

    result =
      case item_type do
        "folder" ->
          reorder_folder(item_id, parent_id, siblings, user)

        "page" ->
          reorder_page(item_id, parent_type, parent_id, siblings, user)
      end

    case result do
      :ok ->
        {folders, pages} = load_sidebar_data(project.id, user)

        {:noreply,
         socket
         |> assign(:sidebar_folders, folders)
         |> assign(:sidebar_pages, pages)
         |> push_event("tree_updated", %{success: true})}

      {:error, reason} ->
        {:noreply,
         socket
         |> Phoenix.LiveView.put_flash(:error, "Failed to reorder: #{reason}")
         |> push_event("tree_updated", %{success: false, message: reason})}
    end
  end

  defp reorder_folder(folder_id, new_parent_id, siblings, user) do
    parent_id = if new_parent_id == "", do: nil, else: new_parent_id

    case Ash.get(Nexus.Content.Folder, folder_id, actor: user) do
      {:ok, folder} ->
        position = find_position(siblings, folder_id)

        case Ash.update(folder, %{parent_id: parent_id, position: position}, actor: user) do
          {:ok, _} ->
            update_sibling_positions(siblings, Nexus.Content.Folder, user)
            :ok

          {:error, _} ->
            {:error, "Failed to update folder"}
        end

      {:error, _} ->
        {:error, "Folder not found"}
    end
  end

  defp reorder_page(page_id, parent_type, parent_id, siblings, user) do
    attrs =
      case parent_type do
        "root" ->
          %{folder_id: nil, parent_page_id: nil}

        "folder" ->
          %{folder_id: parent_id, parent_page_id: nil}

        "page" ->
          %{parent_page_id: parent_id}
      end

    case Ash.get(Nexus.Content.Page, page_id, actor: user) do
      {:ok, page} ->
        position = find_position(siblings, page_id)
        attrs = Map.put(attrs, :position, position)

        case Ash.update(page, attrs, actor: user) do
          {:ok, _} ->
            update_sibling_positions(siblings, Nexus.Content.Page, user)
            :ok

          {:error, _} ->
            {:error, "Failed to update page"}
        end

      {:error, _} ->
        {:error, "Page not found"}
    end
  end

  defp find_position(siblings, item_id) do
    Enum.find_index(siblings, fn %{"id" => id} -> id == item_id end) || 0
  end

  defp update_sibling_positions(siblings, resource, user) do
    siblings
    |> Enum.with_index()
    |> Enum.each(fn {%{"id" => id}, position} ->
      case Ash.get(resource, id, authorize?: false) do
        {:ok, item} ->
          Ash.update(item, %{position: position}, actor: user)

        _ ->
          :ok
      end
    end)
  end

  defp load_sidebar_data(project_id, user) do
    folders =
      case Nexus.Content.Folder.for_project(project_id, actor: user) do
        {:ok, folders} -> folders
        _ -> []
      end

    pages =
      case Nexus.Content.Page.list_for_project(project_id, actor: user) do
        {:ok, pages} -> pages
        _ -> []
      end

    {folders, pages}
  end
end
