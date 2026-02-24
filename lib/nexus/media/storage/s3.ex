defmodule Nexus.Media.Storage.S3 do
  @moduledoc """
  S3-compatible storage backend for the media system.

  Stores files in an S3 bucket using `ExAws.S3`. Configuration is read from
  `Application.get_env(:nexus, :s3, [])` with keys:

    * `:access_key_id` — AWS access key
    * `:secret_access_key` — AWS secret key
    * `:region` — AWS region (default: `"auto"`)
    * `:bucket` — S3 bucket name (required)
    * `:host` — custom S3 endpoint hostname (e.g. for R2/MinIO)
    * `:scheme` — URL scheme (default: `"https://"`)
    * `:prefix` — key prefix inside the bucket (default: `"media"`)

  Objects are stored under `{prefix}/{relative_path}` with the content-type
  header set automatically from the file extension.
  """

  @doc """
  Uploads binary content to S3 at the given relative path.

  The content-type is auto-detected from the file extension. Returns
  `{:ok, relative_path}` on success or `{:error, reason}` on failure.
  """
  @spec store(String.t(), binary(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def store(relative_path, content, opts \\ []) do
    s3_config = s3_config(opts)
    key = s3_key(relative_path, s3_config)
    content_type = Nexus.Media.Storage.mime_type_from_path(relative_path)

    put_opts =
      if content_type do
        [content_type: content_type]
      else
        []
      end

    case ExAws.S3.put_object(s3_config.bucket, key, content, put_opts)
         |> ExAws.request(aws_config(s3_config)) do
      {:ok, _response} -> {:ok, relative_path}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Retrieves file content from S3 at the given relative path.

  Returns `{:ok, binary}` on success, `{:error, :not_found}` if the object
  does not exist, or `{:error, reason}` for other failures.
  """
  @spec get(String.t(), keyword()) :: {:ok, binary()} | {:error, :not_found | term()}
  def get(relative_path, opts \\ []) do
    s3_config = s3_config(opts)
    key = s3_key(relative_path, s3_config)

    case ExAws.S3.get_object(s3_config.bucket, key)
         |> ExAws.request(aws_config(s3_config)) do
      {:ok, %{body: body}} -> {:ok, body}
      {:error, {:http_error, 404, _}} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Deletes an object from S3 at the given relative path.

  Returns `:ok` on success, including when the object does not exist (S3
  delete is idempotent). Returns `{:error, reason}` for other failures.
  """
  @spec delete(String.t(), keyword()) :: :ok | {:error, term()}
  def delete(relative_path, opts \\ []) do
    s3_config = s3_config(opts)
    key = s3_key(relative_path, s3_config)

    case ExAws.S3.delete_object(s3_config.bucket, key)
         |> ExAws.request(aws_config(s3_config)) do
      {:ok, _response} -> :ok
      {:error, {:http_error, 404, _}} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  # --- Private helpers ---

  defp s3_config(_opts) do
    config = Application.get_env(:nexus, :s3, [])

    %{
      access_key_id: Keyword.get(config, :access_key_id),
      secret_access_key: Keyword.get(config, :secret_access_key),
      region: Keyword.get(config, :region, "auto"),
      bucket: Keyword.fetch!(config, :bucket),
      host: Keyword.get(config, :host),
      scheme: Keyword.get(config, :scheme, "https://"),
      prefix: Keyword.get(config, :prefix, "media")
    }
  end

  defp s3_key(relative_path, %{prefix: prefix}) do
    "#{prefix}/#{relative_path}"
  end

  defp aws_config(s3_config) do
    base = [
      access_key_id: s3_config.access_key_id,
      secret_access_key: s3_config.secret_access_key,
      region: s3_config.region
    ]

    base =
      if s3_config.host do
        Keyword.merge(base, host: s3_config.host, scheme: s3_config.scheme)
      else
        base
      end

    base
  end
end
