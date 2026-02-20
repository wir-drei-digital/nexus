defmodule NexusWeb.AshJsonApiRouter do
  use AshJsonApi.Router,
    domains: [Nexus.Projects, Nexus.Content],
    open_api: "/open_api"
end
