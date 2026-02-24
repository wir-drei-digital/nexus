defmodule NexusWeb.MediaController do
  use NexusWeb, :controller

  alias Nexus.Media.Storage

  def show(conn, %{"path" => path_parts}) do
    relative_path = Path.join(path_parts)

    case Storage.get(relative_path) do
      {:ok, content} ->
        content_type = Storage.mime_type_from_path(relative_path)

        conn
        |> put_resp_header("content-type", content_type)
        |> put_resp_header("cache-control", "public, max-age=31536000, immutable")
        |> put_resp_header("etag", etag(relative_path))
        |> send_resp(200, content)

      {:error, _} ->
        send_resp(conn, 404, "Not found")
    end
  end

  defp etag(path), do: "\"#{Base.encode16(:crypto.hash(:md5, path), case: :lower)}\""
end
