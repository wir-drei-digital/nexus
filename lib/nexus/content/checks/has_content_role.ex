defmodule Nexus.Content.Checks.HasContentRole do
  @moduledoc """
  Policy check for content resources that belong to a page (PageVersion, PageLocale).
  Resolves the project through the page relationship for create actions.
  """
  use Ash.Policy.SimpleCheck

  @impl true
  def describe(opts) do
    roles = Keyword.get(opts, :roles, [:admin, :editor])
    "actor has one of #{inspect(roles)} roles on the page's project"
  end

  @impl true
  def match?(nil, _context, _opts), do: false

  def match?(actor, %{changeset: %Ash.Changeset{} = changeset}, opts) do
    roles = Keyword.get(opts, :roles, [:admin, :editor])
    page_id = Ash.Changeset.get_attribute(changeset, :page_id)

    if page_id do
      project_id = Nexus.Checks.MembershipLookup.project_id_for_page(page_id)
      project_id && Nexus.Checks.MembershipLookup.has_role?(actor.id, project_id, roles)
    else
      false
    end
  end

  def match?(_actor, _context, _opts), do: false
end
