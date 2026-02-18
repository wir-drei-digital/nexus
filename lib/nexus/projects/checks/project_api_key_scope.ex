defmodule Nexus.Projects.Checks.ProjectApiKeyScope do
  use Ash.Policy.SimpleCheck

  @impl true
  def describe(opts) do
    scope = Keyword.fetch!(opts, :scope)
    "project API key has #{scope} scope"
  end

  @impl true
  def match?(%Nexus.Projects.ProjectApiKey{} = api_key, _context, opts) do
    required_scope = Keyword.fetch!(opts, :scope)
    :full_access in api_key.scopes or required_scope in api_key.scopes
  end

  def match?(_actor, _context, _opts), do: false
end
