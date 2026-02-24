defmodule Nexus.Media.Storage.Local do
  @moduledoc """
  Local filesystem storage backend for the media system.

  Stores files under a base directory (default: `priv/static/uploads/media`).
  The base directory can be overridden via the `base_dir:` option, which is
  useful for testing.

  All paths are validated to prevent directory traversal attacks.
  """

  @default_base_dir "priv/static/uploads/media"

  @doc """
  Stores binary content at the given relative path.

  Creates any intermediate directories as needed. Returns `{:ok, relative_path}`
  on success, or `{:error, :invalid_path}` if the path attempts directory traversal.
  """
  @spec store(String.t(), binary(), keyword()) :: {:ok, String.t()} | {:error, :invalid_path}
  def store(relative_path, content, opts \\ []) do
    base_dir = Keyword.get(opts, :base_dir, @default_base_dir)

    with :ok <- validate_path(relative_path, base_dir) do
      full_path = Path.join(base_dir, relative_path)
      full_path |> Path.dirname() |> File.mkdir_p!()
      File.write!(full_path, content)
      {:ok, relative_path}
    end
  end

  @doc """
  Reads file content at the given relative path.

  Returns `{:ok, content}` on success, `{:error, :not_found}` if the file does
  not exist, or `{:error, :invalid_path}` for traversal attempts.
  """
  @spec get(String.t(), keyword()) :: {:ok, binary()} | {:error, :not_found | :invalid_path}
  def get(relative_path, opts \\ []) do
    base_dir = Keyword.get(opts, :base_dir, @default_base_dir)

    with :ok <- validate_path(relative_path, base_dir) do
      full_path = Path.join(base_dir, relative_path)

      case File.read(full_path) do
        {:ok, content} -> {:ok, content}
        {:error, :enoent} -> {:error, :not_found}
      end
    end
  end

  @doc """
  Deletes the file at the given relative path.

  Returns `:ok` regardless of whether the file existed.
  Returns `{:error, :invalid_path}` for traversal attempts.
  """
  @spec delete(String.t(), keyword()) :: :ok | {:error, :invalid_path}
  def delete(relative_path, opts \\ []) do
    base_dir = Keyword.get(opts, :base_dir, @default_base_dir)

    with :ok <- validate_path(relative_path, base_dir) do
      full_path = Path.join(base_dir, relative_path)

      case File.rm(full_path) do
        :ok -> :ok
        {:error, :enoent} -> :ok
      end
    end
  end

  defp validate_path(relative_path, base_dir) do
    # Reject absolute paths
    if String.starts_with?(relative_path, "/") do
      {:error, :invalid_path}
    else
      expanded = Path.expand(Path.join(base_dir, relative_path))
      base_expanded = Path.expand(base_dir)

      if String.starts_with?(expanded, base_expanded <> "/") do
        :ok
      else
        {:error, :invalid_path}
      end
    end
  end
end
