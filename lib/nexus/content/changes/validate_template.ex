defmodule Nexus.Content.Changes.ValidateTemplate do
  @moduledoc """
  Validates that the template_slug on a Page exists in the registry
  and is available for the page's project.
  """

  use Ash.Resource.Change

  alias Nexus.Content.Templates.Registry

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      template_slug = Ash.Changeset.get_attribute(changeset, :template_slug)

      cond do
        is_nil(template_slug) ->
          changeset

        not Registry.exists?(template_slug) ->
          Ash.Changeset.add_error(changeset,
            field: :template_slug,
            message: "template '#{template_slug}' does not exist"
          )

        true ->
          validate_project_availability(changeset, template_slug)
      end
    end)
  end

  defp validate_project_availability(changeset, template_slug) do
    project_id = Ash.Changeset.get_attribute(changeset, :project_id)

    case Ash.get(Nexus.Projects.Project, project_id, authorize?: false) do
      {:ok, project} ->
        if template_slug in project.available_templates do
          changeset
        else
          Ash.Changeset.add_error(changeset,
            field: :template_slug,
            message: "template '#{template_slug}' is not available for this project"
          )
        end

      {:error, _} ->
        changeset
    end
  end
end
