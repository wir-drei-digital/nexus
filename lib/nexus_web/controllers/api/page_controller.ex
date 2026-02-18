defmodule NexusWeb.Api.PageController do
  use NexusWeb, :controller

  require Ash.Query

  alias Nexus.Content.Templates.Renderer

  def index(conn, %{"slug" => project_slug} = params) do
    with {:ok, project} <- get_project(project_slug) do
      actor = conn.assigns[:current_project_api_key] || conn.assigns[:current_user]

      pages =
        Nexus.Content.Page
        |> Ash.Query.for_read(:list_for_project, %{project_id: project.id}, actor: actor)
        |> maybe_filter_by_folder(params)
        |> Ash.read!(authorize?: actor != nil)

      json(conn, %{
        data:
          Enum.map(pages, fn page ->
            %{
              id: page.id,
              slug: to_string(page.slug),
              full_path: to_string(page.full_path),
              status: page.status,
              folder_id: page.folder_id,
              template_slug: page.template_slug
            }
          end)
      })
    else
      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Project not found"})
    end
  end

  def show(conn, %{"slug" => project_slug, "path" => path_parts}) do
    full_path = Enum.join(path_parts, "/")

    with {:ok, project} <- get_project(project_slug),
         {:ok, page} <- get_page(project, full_path, conn),
         locale <- conn.params["locale"] || project.default_locale,
         {:ok, version} <- get_published_version(page, locale) do
      html_content = Renderer.render(page.template_slug, version.template_data)

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
          template_slug: page.template_slug,
          template_data: version.template_data,
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

  defp maybe_filter_by_folder(query, %{"folder" => folder_path}) when folder_path != "" do
    Ash.Query.filter(query, full_path: [starts_with: folder_path])
  end

  defp maybe_filter_by_folder(query, _params), do: query

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
