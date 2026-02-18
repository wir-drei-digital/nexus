defmodule NexusWeb.Api.PageRenderController do
  use NexusWeb, :controller

  alias Nexus.Content.BlockRenderer

  def render_page(conn, %{"slug" => project_slug, "path" => path_parts}) do
    full_path = Enum.join(path_parts, "/")

    with {:ok, project} <- get_project(project_slug),
         {:ok, page} <- get_page(project, full_path, conn),
         locale <- conn.params["locale"] || project.default_locale,
         {:ok, version} <- get_published_version(page, locale) do
      html_content = BlockRenderer.render_blocks(version.blocks)

      json(conn, %{
        data: %{
          title: version.title,
          locale: version.locale,
          meta_description: version.meta_description,
          meta_keywords: version.meta_keywords,
          og_title: version.og_title,
          og_description: version.og_description,
          og_image_url: version.og_image_url,
          html: html_content,
          version_number: version.version_number
        }
      })
    else
      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Not found"})

      {:error, :no_published_version} ->
        conn |> put_status(:not_found) |> json(%{error: "No published version for this locale"})
    end
  end

  def tree(conn, %{"slug" => project_slug}) do
    with {:ok, project} <- get_project(project_slug) do
      actor = conn.assigns[:current_project_api_key] || conn.assigns[:current_user]

      directories =
        Nexus.Content.Directory
        |> Ash.Query.for_read(:for_project, %{project_id: project.id}, actor: actor)
        |> Ash.read!(authorize?: actor != nil)

      json(conn, %{
        data:
          Enum.map(directories, fn dir ->
            %{
              id: dir.id,
              name: dir.name,
              slug: to_string(dir.slug),
              full_path: to_string(dir.full_path),
              parent_id: dir.parent_id,
              position: dir.position
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

  defp get_page(project, full_path, conn) do
    actor = conn.assigns[:current_project_api_key] || conn.assigns[:current_user]

    case Nexus.Content.Page.get_by_path(project.id, full_path, actor: actor) do
      {:ok, page} -> {:ok, page}
      {:error, _} -> {:error, :not_found}
    end
  end

  defp get_published_version(page, locale) do
    case Ash.get(Nexus.Content.PageLocale, %{page_id: page.id, locale: locale},
           authorize?: false,
           load: [:published_version]
         ) do
      {:ok, %{published_version: %{id: _} = version}} -> {:ok, version}
      _ -> {:error, :no_published_version}
    end
  end
end
