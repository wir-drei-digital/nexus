defmodule Nexus.Content.Changes.ValidateTemplateData do
  @moduledoc """
  Validates that template_data conforms to the page's template definition.
  Looks up the template_slug from the associated page.
  """

  use Ash.Resource.Change

  alias Nexus.Content.Templates.Validator

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      template_data = Ash.Changeset.get_attribute(changeset, :template_data)
      page_id = Ash.Changeset.get_attribute(changeset, :page_id)

      if template_data && page_id do
        validate_data(changeset, page_id, template_data)
      else
        changeset
      end
    end)
  end

  defp validate_data(changeset, page_id, template_data) do
    case Ash.get(Nexus.Content.Page, page_id, authorize?: false) do
      {:ok, page} ->
        case Validator.validate(page.template_slug, template_data) do
          :ok ->
            changeset

          {:error, errors} ->
            Enum.reduce(errors, changeset, fn {field, message}, cs ->
              Ash.Changeset.add_error(cs, field: String.to_atom(field), message: message)
            end)
        end

      {:error, _} ->
        changeset
    end
  end
end
