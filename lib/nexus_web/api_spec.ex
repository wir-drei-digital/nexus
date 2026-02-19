defmodule NexusWeb.ApiSpec do
  @moduledoc """
  OpenAPI specification for the Nexus public API (v1).
  """
  alias OpenApiSpex.{Info, OpenApi, Paths, Server}

  @behaviour OpenApi

  @impl OpenApi
  def spec do
    %OpenApi{
      info: %Info{
        title: "Nexus API",
        version: "1.0.0",
        description: "Public content delivery API for Nexus CMS."
      },
      servers: [%Server{url: "/api/v1"}],
      paths: Paths.from_router(NexusWeb.Router)
    }
    |> OpenApiSpex.resolve_schema_modules()
  end
end
