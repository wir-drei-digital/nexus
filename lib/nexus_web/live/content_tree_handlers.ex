defmodule NexusWeb.ContentTreeHandlers do
  @moduledoc """
  Shared event handlers for content tree drag-and-drop operations.
  Import this module's handle_event/3 into LiveViews that use the project layout.
  """
  import Phoenix.LiveView
  import Phoenix.Component, only: [assign: 3]

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
        "directory" ->
          reorder_directory(item_id, parent_id, siblings, user)

        "page" ->
          reorder_page(item_id, parent_type, parent_id, siblings, user)
      end

    case result do
      :ok ->
        {directories, pages} = load_sidebar_data(project.id, user)

        {:noreply,
         socket
         |> assign(:sidebar_directories, directories)
         |> assign(:sidebar_pages, pages)
         |> push_event("tree_updated", %{success: true})}

      {:error, reason} ->
        {:noreply,
         socket
         |> Phoenix.LiveView.put_flash(:error, "Failed to reorder: #{reason}")
         |> push_event("tree_updated", %{success: false, message: reason})}
    end
  end

  defp reorder_directory(directory_id, new_parent_id, siblings, user) do
    parent_id = if new_parent_id == "", do: nil, else: new_parent_id

    case Ash.get(Nexus.Content.Directory, directory_id, actor: user) do
      {:ok, directory} ->
        position = find_position(siblings, directory_id)

        case Ash.update(directory, %{parent_id: parent_id, position: position}, actor: user) do
          {:ok, _} ->
            update_sibling_positions(siblings, Nexus.Content.Directory, user)
            :ok

          {:error, _} ->
            {:error, "Failed to update directory"}
        end

      {:error, _} ->
        {:error, "Directory not found"}
    end
  end

  defp reorder_page(page_id, parent_type, parent_id, siblings, user) do
    attrs =
      case parent_type do
        "root" ->
          %{directory_id: nil, parent_page_id: nil}

        "directory" ->
          %{directory_id: parent_id, parent_page_id: nil}

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
    directories =
      case Nexus.Content.Directory.for_project(project_id, actor: user) do
        {:ok, dirs} -> dirs
        _ -> []
      end

    pages =
      case Nexus.Content.Page.list_for_project(project_id, actor: user) do
        {:ok, pages} -> pages
        _ -> []
      end

    {directories, pages}
  end
end
