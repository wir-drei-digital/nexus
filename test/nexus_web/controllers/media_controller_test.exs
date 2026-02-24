defmodule NexusWeb.MediaControllerTest do
  use NexusWeb.ConnCase, async: true

  alias Nexus.Media.Storage

  @test_content <<0xFF, 0xD8, 0xFF, 0xE0>> <> "fake jpeg data"

  setup do
    path = "test-project/test-file-#{System.unique_integer([:positive])}.jpg"
    {:ok, _} = Storage.store(path, @test_content)
    on_exit(fn -> Storage.delete(path) end)
    %{path: path}
  end

  test "serves an existing file with correct headers", %{conn: conn, path: path} do
    conn = get(conn, "/media/#{path}")
    assert conn.status == 200
    assert get_resp_header(conn, "content-type") == ["image/jpeg"]
    assert get_resp_header(conn, "cache-control") == ["public, max-age=31536000, immutable"]
    assert conn.resp_body == @test_content
  end

  test "returns 404 for missing file", %{conn: conn} do
    conn = get(conn, "/media/nonexistent/missing.jpg")
    assert conn.status == 404
  end

  test "sets etag header", %{conn: conn, path: path} do
    conn = get(conn, "/media/#{path}")
    assert [etag] = get_resp_header(conn, "etag")
    assert String.starts_with?(etag, "\"")
    assert String.ends_with?(etag, "\"")
  end
end
