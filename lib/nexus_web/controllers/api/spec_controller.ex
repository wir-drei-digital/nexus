defmodule NexusWeb.Api.SpecController do
  use NexusWeb, :controller

  def index(conn, _params) do
    spec = NexusWeb.ApiSpec.spec()
    json(conn, spec)
  end
end
