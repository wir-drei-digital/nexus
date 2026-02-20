defmodule Nexus.Content.Actions.GetPublishedContent do
  @moduledoc """
  Action handler that retrieves rendered published page content.

  This replaces the logic from PageController.show and returns composite data
  including rendered HTML from the template.
  """

  require Ash.Query

  alias Nexus.Content.Templates.Renderer

  def run(input, _opts, context) do
    project_slug = Ash.Changeset.get_argument(input, :project_slug)
    path = Ash.Changeset.get_argument(input, :path)
    locale = Ash.Changeset.get_argument(input, :locale)
    actor = context[:actor]

    with {:ok, project} <- get_project(project_slug),
         {:ok, page} <- get_page(project, path, actor),
         locale <- locale || project.default_locale,
         {:ok, version} <- get_published_version(page, locale) do
      html_content = Renderer.render(page.template_slug, version.template_data)

      {:ok,
       %{
         id: version.id,
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
       }}
    else
      {:error, :not_found} ->
        {:error, Ash.Error.Query.NotFound.exception(primary_key: path)}

      {:error, :no_published_version} ->
        {:error,
         Ash.Error.Invalid.exception(
           message: "No published version for this locale",
           class: :invalid
         )}

      error ->
        error
    end
  end

  defp get_project(slug) do
    case Nexus.Projects.Project.get_by_slug(slug, authorize?: false) do
      {:ok, project} -> {:ok, project}
      {:error, _} -> {:error, :not_found}
    end
  end

  defp get_page(project, full_path, actor) do
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
