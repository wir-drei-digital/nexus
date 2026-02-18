defmodule NexusWeb.Api.FolderController do
  use NexusWeb, :controller

  def index(conn, %{"slug" => project_slug}) do
    with {:ok, project} <- get_project(project_slug) do
      actor = conn.assigns[:current_project_api_key] || conn.assigns[:current_user]

      folders =
        Nexus.Content.Folder
        |> Ash.Query.for_read(:for_project, %{project_id: project.id}, actor: actor)
        |> Ash.read!(authorize?: actor != nil)

      json(conn, %{
        data:
          Enum.map(folders, fn folder ->
            %{
              id: folder.id,
              name: folder.name,
              slug: to_string(folder.slug),
              full_path: to_string(folder.full_path),
              parent_id: folder.parent_id,
              position: folder.position
            }
          end)
      })
    else
      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Project not found"})
    end
  end

  defp get_project(slug) do
    case Nexus.Projects.Project.get_by_slug(slug, authorize?: false) do
      {:ok, project} -> {:ok, project}
      {:error, _} -> {:error, :not_found}
    end
  end
end
