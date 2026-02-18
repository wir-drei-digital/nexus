defmodule NexusWeb.Api.ProjectController do
  use NexusWeb, :controller

  def show(conn, %{"slug" => slug}) do
    case Nexus.Projects.Project.get_by_slug(slug, authorize?: false) do
      {:ok, project} ->
        json(conn, %{
          data: %{
            name: project.name,
            slug: to_string(project.slug),
            description: project.description,
            default_locale: project.default_locale,
            available_locales: project.available_locales,
            available_templates: project.available_templates
          }
        })

      {:error, _} ->
        conn |> put_status(:not_found) |> json(%{error: "Project not found"})
    end
  end
end
