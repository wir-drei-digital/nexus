defmodule NexusWeb.MediaLive.PickerComponent do
  @moduledoc """
  A reusable LiveComponent that renders a modal overlay with a media gallery grid.

  Users can select an existing image or upload a new one. On selection, the
  component sends `{:media_selected, media_item, meta}` to the parent LiveView.

  ## Usage

      <.live_component
        :if={@show_media_picker}
        module={NexusWeb.MediaLive.PickerComponent}
        id="media-picker"
        project={@project}
        current_user={@current_user}
        meta={@media_picker_meta}
      />

  The parent must handle:

      def handle_info({:media_selected, item, meta}, socket)
      def handle_info({:close_media_picker}, socket)
  """

  use NexusWeb, :live_component

  alias Nexus.Media.{MediaItem, Processor, Storage}

  @impl true
  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign_new(:items, fn ->
        load_items(assigns.project.id, assigns.current_user)
      end)
      |> allow_upload(:picker_uploads,
        accept: ~w(.jpg .jpeg .png .gif .webp .svg),
        max_entries: 5,
        max_file_size: 20_000_000
      )

    {:ok, socket}
  end

  # ── Upload events ────────────────────────────────────────────────

  @impl true
  def handle_event("validate_picker_uploads", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("save_picker_uploads", _params, socket) do
    project = socket.assigns.project
    user = socket.assigns.current_user
    meta = socket.assigns.meta

    uploaded_items =
      consume_uploaded_entries(socket, :picker_uploads, fn %{path: path}, entry ->
        content = File.read!(path)
        item_id = Ash.UUID.generate()
        storage_path = Storage.generate_path(project.id, item_id, entry.client_name)
        mime_type = Storage.mime_type_from_path(entry.client_name) || "application/octet-stream"

        case Storage.store(storage_path, content) do
          {:ok, _} ->
            item =
              MediaItem.create!(
                %{
                  filename: entry.client_name,
                  file_path: storage_path,
                  mime_type: mime_type,
                  file_size: byte_size(content),
                  storage_backend: to_string(Storage.backend()),
                  project_id: project.id,
                  uploaded_by_id: user.id
                },
                actor: user
              )

            Processor.enqueue(item)
            {:ok, item}

          {:error, reason} ->
            {:postpone, reason}
        end
      end)

    new_items = Enum.filter(uploaded_items, &match?(%MediaItem{}, &1))

    case new_items do
      [item | _] ->
        # Auto-select the first just-uploaded item
        send(self(), {:media_selected, item, meta})
        {:noreply, socket}

      [] ->
        {:noreply, socket}
    end
  end

  # ── Selection events ─────────────────────────────────────────────

  @impl true
  def handle_event("select_image", %{"id" => id}, socket) do
    item = Enum.find(socket.assigns.items, &(&1.id == id))

    if item do
      send(self(), {:media_selected, item, socket.assigns.meta})
    end

    {:noreply, socket}
  end

  @impl true
  def handle_event("close_picker", _params, socket) do
    send(self(), {:close_media_picker})
    {:noreply, socket}
  end

  # ── Helpers ──────────────────────────────────────────────────────

  defp load_items(project_id, user) do
    case MediaItem.list_for_project(project_id, actor: user) do
      {:ok, items} -> items
      _ -> []
    end
  end

  defp thumb_url(item) do
    path =
      case Map.get(item.variants || %{}, "thumb") do
        nil -> item.file_path
        variant_path -> variant_path
      end

    Storage.url(path)
  end

  defp upload_error_to_string(:too_large), do: "File is too large (max 20 MB)"
  defp upload_error_to_string(:too_many_files), do: "Too many files (max 5)"
  defp upload_error_to_string(:not_accepted), do: "File type not accepted"
  defp upload_error_to_string(err), do: "Error: #{inspect(err)}"

  # ── Template ─────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <div class="fixed inset-0 z-50 flex items-center justify-center p-4" id={@id}>
      <%!-- Backdrop --%>
      <div class="absolute inset-0 bg-black/50" phx-click="close_picker" phx-target={@myself} />

      <%!-- Modal card --%>
      <div class="relative bg-base-100 rounded-xl shadow-2xl w-full max-w-3xl max-h-[80vh] flex flex-col">
        <%!-- Header --%>
        <div class="flex items-center justify-between px-5 py-3 border-b border-base-200">
          <h3 class="font-semibold">Select Image</h3>
          <button phx-click="close_picker" phx-target={@myself} class="btn btn-ghost btn-sm">
            <.icon name="hero-x-mark" class="size-5" />
          </button>
        </div>

        <%!-- Body (scrollable) --%>
        <div class="flex-1 overflow-y-auto p-5">
          <%!-- Compact upload zone --%>
          <form
            id="picker-upload-form"
            phx-submit="save_picker_uploads"
            phx-change="validate_picker_uploads"
            phx-target={@myself}
          >
            <div
              class="border-2 border-dashed border-base-content/20 rounded-lg p-4 mb-4 text-center hover:border-primary/50 transition-colors"
              phx-drop-target={@uploads.picker_uploads.ref}
            >
              <div class="flex items-center justify-center gap-3">
                <.icon name="hero-cloud-arrow-up" class="size-6 text-base-content/30" />
                <p class="text-sm text-base-content/60">
                  Drop files or
                </p>
                <label class="btn btn-primary btn-xs">
                  <.icon name="hero-plus" class="size-3" /> Choose Files
                  <.live_file_input upload={@uploads.picker_uploads} class="hidden" />
                </label>
              </div>
              <p class="text-xs text-base-content/40 mt-1">
                JPG, PNG, GIF, WebP, SVG — up to 20 MB each
              </p>
            </div>

            <%!-- Upload entries / progress --%>
            <div :if={@uploads.picker_uploads.entries != []} class="mb-4 space-y-2">
              <div
                :for={entry <- @uploads.picker_uploads.entries}
                class="flex items-center gap-3 bg-base-200 rounded-lg px-3 py-2"
              >
                <.icon name="hero-document" class="size-4 text-base-content/50 shrink-0" />
                <div class="flex-1 min-w-0">
                  <p class="text-sm truncate">{entry.client_name}</p>
                  <div class="w-full bg-base-300 rounded-full h-1 mt-1">
                    <div
                      class="bg-primary h-1 rounded-full transition-all"
                      style={"width: #{entry.progress}%"}
                    >
                    </div>
                  </div>
                </div>
                <span class="text-xs text-base-content/50 shrink-0">{entry.progress}%</span>
                <button
                  type="button"
                  phx-click="cancel-upload"
                  phx-value-ref={entry.ref}
                  phx-target={@myself}
                  class="btn btn-ghost btn-xs"
                  aria-label="Cancel upload"
                >
                  <.icon name="hero-x-mark" class="size-3" />
                </button>
              </div>

              <%!-- Upload errors --%>
              <p
                :for={err <- upload_errors(@uploads.picker_uploads)}
                class="text-error text-sm"
              >
                {upload_error_to_string(err)}
              </p>

              <button type="submit" class="btn btn-primary btn-xs mt-1">
                <.icon name="hero-arrow-up-tray" class="size-3" />
                Upload {length(@uploads.picker_uploads.entries)} file(s)
              </button>
            </div>
          </form>

          <%!-- Empty state --%>
          <div :if={@items == []} class="text-center py-12">
            <.icon name="hero-photo" class="size-12 mx-auto text-base-content/20 mb-3" />
            <p class="text-base-content/60 text-sm">No images yet. Upload one above.</p>
          </div>

          <%!-- Thumbnail grid --%>
          <div
            :if={@items != []}
            class="grid grid-cols-3 sm:grid-cols-4 lg:grid-cols-5 gap-2"
          >
            <div
              :for={item <- @items}
              class="group relative bg-base-200 rounded-lg overflow-hidden cursor-pointer border-2 border-transparent hover:border-primary transition-all aspect-square"
              phx-click="select_image"
              phx-value-id={item.id}
              phx-target={@myself}
            >
              <img
                src={thumb_url(item)}
                alt={item.alt_text || item.filename}
                class="w-full h-full object-cover"
                loading="lazy"
              />

              <%!-- Filename overlay --%>
              <div class="absolute inset-x-0 bottom-0 bg-gradient-to-t from-black/60 to-transparent px-2 py-1.5 opacity-0 group-hover:opacity-100 transition-opacity">
                <p class="text-white text-xs truncate">{item.filename}</p>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
