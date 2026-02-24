defmodule Nexus.Media.Storage do
  @moduledoc """
  Storage abstraction layer for the media system.

  Delegates to the configured backend (`:local` or `:s3`).
  The backend is configured via `Application.get_env(:nexus, :storage_backend, :local)`.
  """

  @type relative_path :: String.t()

  @mime_types %{
    "jpg" => "image/jpeg",
    "jpeg" => "image/jpeg",
    "png" => "image/png",
    "gif" => "image/gif",
    "webp" => "image/webp",
    "svg" => "image/svg+xml"
  }

  @doc """
  Returns the configured storage backend atom (`:local` or `:s3`).
  """
  @spec backend() :: :local | :s3
  def backend do
    Application.get_env(:nexus, :storage_backend, :local)
  end

  @doc """
  Stores content at the given relative path via the configured backend.
  """
  @spec store(relative_path(), binary(), keyword()) :: {:ok, relative_path()} | {:error, term()}
  def store(relative_path, content, opts \\ []) do
    backend_module().store(relative_path, content, opts)
  end

  @doc """
  Retrieves content at the given relative path via the configured backend.
  """
  @spec get(relative_path(), keyword()) :: {:ok, binary()} | {:error, :not_found | term()}
  def get(relative_path, opts \\ []) do
    backend_module().get(relative_path, opts)
  end

  @doc """
  Deletes the file at the given relative path via the configured backend.
  """
  @spec delete(relative_path(), keyword()) :: :ok | {:error, term()}
  def delete(relative_path, opts \\ []) do
    backend_module().delete(relative_path, opts)
  end

  @doc """
  Returns the public proxy URL for the given relative path.

  ## Examples

      iex> Nexus.Media.Storage.url("project1/item1.jpg")
      "/media/project1/item1.jpg"
  """
  @spec url(relative_path()) :: String.t()
  def url(relative_path) do
    "/media/#{relative_path}"
  end

  @doc """
  Generates a storage path from project ID, item ID, filename, and optional variant.

  The extension is extracted from the original filename.

  ## Examples

      iex> Nexus.Media.Storage.generate_path("proj-uuid", "item-uuid", "photo.jpg")
      "proj-uuid/item-uuid.jpg"

      iex> Nexus.Media.Storage.generate_path("proj-uuid", "item-uuid", "photo.jpg", "thumb")
      "proj-uuid/item-uuid_thumb.jpg"
  """
  @spec generate_path(String.t(), String.t(), String.t(), String.t() | nil) :: relative_path()
  def generate_path(project_id, item_id, filename, variant \\ nil) do
    ext = Path.extname(filename)

    basename =
      case variant do
        nil -> "#{item_id}#{ext}"
        variant -> "#{item_id}_#{variant}#{ext}"
      end

    Path.join(project_id, basename)
  end

  @doc """
  Detects MIME type from a file path's extension.

  Supports: jpg, jpeg, png, gif, webp, svg.
  Returns `nil` for unrecognized extensions.

  ## Examples

      iex> Nexus.Media.Storage.mime_type_from_path("photo.jpg")
      "image/jpeg"

      iex> Nexus.Media.Storage.mime_type_from_path("file.xyz")
      nil
  """
  @spec mime_type_from_path(String.t()) :: String.t() | nil
  def mime_type_from_path(path) do
    path
    |> Path.extname()
    |> String.trim_leading(".")
    |> String.downcase()
    |> then(&Map.get(@mime_types, &1))
  end

  @backend_modules %{
    local: Nexus.Media.Storage.Local
  }

  defp backend_module do
    Map.fetch!(@backend_modules, backend())
  end
end
