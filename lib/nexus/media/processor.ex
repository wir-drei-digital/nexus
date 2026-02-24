defmodule Nexus.Media.Processor do
  @moduledoc """
  Oban worker that processes uploaded images — extracting metadata
  (width/height) and generating thumbnail, medium, and large variants
  using the `image` hex package.

  ## Variant sizes

    * `thumb`  — 300px wide
    * `medium` — 800px wide
    * `large`  — 1600px wide

  Only variants smaller than the original image width are generated.
  SVG images are marked as ready immediately with no variants.
  """

  use Oban.Worker, queue: :media_processing, max_attempts: 3

  alias Nexus.Media.{MediaItem, Storage}

  require Logger

  @variants [{"thumb", 300}, {"medium", 800}, {"large", 1600}]

  @doc """
  Enqueues a processing job for the given MediaItem.
  """
  @spec enqueue(MediaItem.t()) :: {:ok, Oban.Job.t()} | {:error, term()}
  def enqueue(%MediaItem{} = item) do
    %{media_item_id: item.id}
    |> __MODULE__.new()
    |> Oban.insert()
  end

  @doc """
  Processes a MediaItem synchronously — extracts metadata, generates
  variants, and updates the resource. Useful for testing.

  Returns `:ok` on success or `{:error, reason}` on failure.
  """
  @spec process(MediaItem.t()) :: :ok | {:error, term()}
  def process(%MediaItem{} = item) do
    set_status(item, :processing)

    case do_process(item) do
      :ok ->
        :ok

      {:error, reason} = error ->
        Logger.error("Media processing failed for #{item.id}: #{inspect(reason)}")
        set_status(item, :error)
        error
    end
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"media_item_id" => media_item_id}}) do
    case Ash.get(MediaItem, media_item_id, authorize?: false) do
      {:ok, item} ->
        process(item)

      {:error, reason} ->
        Logger.error("Media item #{media_item_id} not found: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # -- Private ---------------------------------------------------------------

  defp do_process(%MediaItem{mime_type: "image/svg+xml"} = item) do
    update_item(item, %{status: :ready, variants: %{}})
    :ok
  end

  defp do_process(%MediaItem{} = item) do
    with {:ok, content} <- Storage.get(item.file_path),
         {:ok, image} <- Image.from_binary(content),
         {width, height, _bands} <- Image.shape(image) do
      ext = Path.extname(item.file_path)
      base_path = String.replace_suffix(item.file_path, ext, "")

      variants =
        @variants
        |> Enum.filter(fn {_name, max_width} -> width > max_width end)
        |> Enum.reduce(%{}, fn {name, max_width}, acc ->
          case generate_variant(image, base_path, ext, name, max_width) do
            {:ok, variant_path} ->
              Map.put(acc, name, variant_path)

            {:error, reason} ->
              Logger.warning(
                "Failed to generate #{name} variant for #{item.id}: #{inspect(reason)}"
              )

              acc
          end
        end)

      update_item(item, %{
        status: :ready,
        width: width,
        height: height,
        variants: variants
      })

      :ok
    end
  end

  defp generate_variant(image, base_path, ext, name, max_width) do
    variant_path = "#{base_path}_#{name}#{ext}"

    with {:ok, resized} <- Image.thumbnail(image, max_width),
         {:ok, binary} <- Image.write(resized, :memory, suffix: ext) do
      Storage.store(variant_path, binary)
    end
  end

  defp set_status(item, status) do
    update_item(item, %{status: status})
  end

  defp update_item(item, attrs) do
    item
    |> Ash.Changeset.for_update(:update_status, attrs)
    |> Ash.update!(authorize?: false)
  end
end
