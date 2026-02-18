defmodule NexusWeb.Plugs.ProjectApiKeyAuth do
  @moduledoc """
  Authenticates requests using project API keys.

  Looks for a Bearer token in the Authorization header, hashes it,
  and looks up the matching ProjectApiKey. Sets it as the actor if valid.
  """
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         hash = :crypto.hash(:sha256, token),
         {:ok, api_key} <- find_api_key(hash),
         true <- api_key.is_active,
         true <- not_expired?(api_key) do
      update_last_used(api_key)

      conn
      |> assign(:current_project_api_key, api_key)
      |> Ash.PlugHelpers.set_actor(api_key)
    else
      _ -> conn
    end
  end

  defp find_api_key(hash) do
    import Ecto.Query

    query =
      from k in "project_api_keys",
        where: k.key_hash == ^hash and k.is_active == true,
        select: k.id

    case Nexus.Repo.one(query) do
      nil ->
        {:error, :not_found}

      id ->
        Ash.get(Nexus.Projects.ProjectApiKey, id,
          authorize?: false,
          load: [:project]
        )
    end
  end

  defp not_expired?(%{expires_at: nil}), do: true

  defp not_expired?(%{expires_at: expires_at}) do
    DateTime.compare(expires_at, DateTime.utc_now()) == :gt
  end

  defp update_last_used(api_key) do
    import Ecto.Query

    from("project_api_keys", where: [id: ^api_key.id])
    |> Nexus.Repo.update_all(set: [last_used_at: DateTime.utc_now()])
  end
end
