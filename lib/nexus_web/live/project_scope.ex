defmodule NexusWeb.ProjectScope do
  @moduledoc """
  On_mount hook that loads a project from the URL slug and assigns it.
  Also loads sidebar tree data (folders + pages) for the project layout.
  """
  import Phoenix.Component
  import Phoenix.LiveView

  def on_mount(:default, %{"slug" => slug}, _session, socket) do
    user = socket.assigns.current_user

    case Nexus.Projects.Project.get_by_slug(slug, actor: user) do
      {:ok, project} ->
        membership = get_membership(project.id, user.id)
        {sidebar_folders, sidebar_pages} = load_sidebar_data(project.id, user)

        {:cont,
         socket
         |> assign(:project, project)
         |> assign(:membership, membership)
         |> assign(:project_role, membership && membership.role)
         |> assign(:sidebar_folders, sidebar_folders)
         |> assign(:sidebar_pages, sidebar_pages)
         |> assign(:creating_content_type, nil)}

      {:error, _} ->
        {:halt, redirect(socket, to: "/admin")}
    end
  end

  def on_mount(:default, _params, _session, socket) do
    {:cont, socket}
  end

  defp get_membership(project_id, user_id) do
    require Ash.Query

    Nexus.Projects.Membership
    |> Ash.Query.for_read(:read, %{}, authorize?: false)
    |> Ash.Query.filter(project_id == ^project_id and user_id == ^user_id)
    |> Ash.read_one()
    |> case do
      {:ok, membership} -> membership
      _ -> nil
    end
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
