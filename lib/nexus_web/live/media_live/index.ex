defmodule NexusWeb.MediaLive.Index do
  use NexusWeb, :live_view

  alias Nexus.Media.{MediaItem, Processor, Storage}

  on_mount {NexusWeb.LiveUserAuth, :live_user_required}
  on_mount {NexusWeb.ProjectScope, :default}

  @impl true
  def mount(_params, _session, socket) do
    project = socket.assigns.project
    user = socket.assigns.current_user

    items = load_items(project.id, user)

    {:ok,
     socket
     |> assign(:page_title, "Media")
     |> assign(:breadcrumbs, [{"Media", nil}])
     |> assign(:items, items)
     |> assign(:selected_item, nil)
     |> allow_upload(:media_uploads,
       accept: ~w(.jpg .jpeg .png .gif .webp .svg),
       max_entries: 10,
       max_file_size: 20_000_000
     )}
  end

  # ── Content tree events (sidebar) ──────────────────────────────

  @impl true
  def handle_event(event, params, socket)
      when event in ~w(reorder_tree_item start_creating_page start_creating_folder cancel_inline_create save_inline_content) do
    NexusWeb.ContentTreeHandlers.handle_event(event, params, socket)
  end

  # ── Upload events ──────────────────────────────────────────────

  @impl true
  def handle_event("validate_uploads", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("save_uploads", _params, socket) do
    project = socket.assigns.project
    user = socket.assigns.current_user

    uploaded_items =
      consume_uploaded_entries(socket, :media_uploads, fn %{path: path}, entry ->
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
    items = new_items ++ socket.assigns.items

    {:noreply,
     socket
     |> assign(:items, items)
     |> put_flash(:info, "#{length(new_items)} file(s) uploaded")}
  end

  # ── Selection events ───────────────────────────────────────────

  @impl true
  def handle_event("select_item", %{"id" => id}, socket) do
    item = Enum.find(socket.assigns.items, &(&1.id == id))
    {:noreply, assign(socket, :selected_item, item)}
  end

  @impl true
  def handle_event("deselect_item", _params, socket) do
    {:noreply, assign(socket, :selected_item, nil)}
  end

  # ── Alt text ───────────────────────────────────────────────────

  @impl true
  def handle_event("update_alt_text", %{"alt_text" => text}, socket) do
    item = socket.assigns.selected_item
    user = socket.assigns.current_user

    case MediaItem.update_alt_text(item, %{alt_text: text}, actor: user) do
      {:ok, updated} ->
        items =
          Enum.map(socket.assigns.items, fn i -> if i.id == updated.id, do: updated, else: i end)

        {:noreply,
         socket
         |> assign(:items, items)
         |> assign(:selected_item, updated)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to update alt text")}
    end
  end

  # ── Copy URL ───────────────────────────────────────────────────

  @impl true
  def handle_event("copy_url", %{"id" => id}, socket) do
    item = Enum.find(socket.assigns.items, &(&1.id == id))

    url =
      case item do
        nil -> ""
        item -> media_url(item, "medium")
      end

    {:noreply, push_event(socket, "copy_to_clipboard", %{text: url})}
  end

  # ── Delete ─────────────────────────────────────────────────────

  @impl true
  def handle_event("delete_item", %{"id" => id}, socket) do
    item = Enum.find(socket.assigns.items, &(&1.id == id))
    user = socket.assigns.current_user

    if item do
      # Delete variant files
      for {_name, variant_path} <- item.variants || %{} do
        Storage.delete(variant_path)
      end

      # Delete original file
      Storage.delete(item.file_path)

      # Destroy the record
      case MediaItem.destroy(item, actor: user) do
        :ok ->
          items = Enum.reject(socket.assigns.items, &(&1.id == id))

          selected =
            if socket.assigns.selected_item && socket.assigns.selected_item.id == id,
              do: nil,
              else: socket.assigns.selected_item

          {:noreply,
           socket
           |> assign(:items, items)
           |> assign(:selected_item, selected)
           |> put_flash(:info, "File deleted")}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Failed to delete file")}
      end
    else
      {:noreply, socket}
    end
  end

  # ── Helpers ────────────────────────────────────────────────────

  defp load_items(project_id, user) do
    case MediaItem.list_for_project(project_id, actor: user) do
      {:ok, items} -> items
      _ -> []
    end
  end

  defp media_url(item, preferred_variant) do
    path =
      case Map.get(item.variants || %{}, preferred_variant) do
        nil -> item.file_path
        variant_path -> variant_path
      end

    Storage.url(path)
  end

  defp human_file_size(nil), do: "Unknown"

  defp human_file_size(bytes) when bytes < 1024,
    do: "#{bytes} B"

  defp human_file_size(bytes) when bytes < 1_048_576,
    do: "#{Float.round(bytes / 1024, 1)} KB"

  defp human_file_size(bytes),
    do: "#{Float.round(bytes / 1_048_576, 1)} MB"

  defp status_badge_class(:ready), do: "badge-success"
  defp status_badge_class(:pending), do: "badge-warning"
  defp status_badge_class(:processing), do: "badge-info"
  defp status_badge_class(:error), do: "badge-error"
  defp status_badge_class(_), do: "badge-neutral"

  # ── Template ───────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.project
      flash={@flash}
      project={@project}
      project_role={@project_role}
      sidebar_folders={@sidebar_folders}
      sidebar_pages={@sidebar_pages}
      page_titles={@page_titles}
      creating_content_type={@creating_content_type}
      breadcrumbs={@breadcrumbs}
    >
      <div class="flex h-full">
        <%!-- Main area --%>
        <div class="flex-1 overflow-y-auto p-6">
          <%!-- Upload zone --%>
          <form
            id="upload-form"
            phx-submit="save_uploads"
            phx-change="validate_uploads"
          >
            <div
              class="border-2 border-dashed border-base-content/20 rounded-xl p-8 mb-6 text-center hover:border-primary/50 transition-colors"
              phx-drop-target={@uploads.media_uploads.ref}
            >
              <.icon name="hero-cloud-arrow-up" class="size-10 mx-auto text-base-content/30 mb-3" />
              <p class="text-base-content/60 mb-3">
                Drag and drop files here, or
              </p>
              <label class="btn btn-primary btn-sm">
                <.icon name="hero-plus" class="size-4" /> Choose Files
                <.live_file_input upload={@uploads.media_uploads} class="hidden" />
              </label>
              <p class="text-xs text-base-content/40 mt-2">
                JPG, PNG, GIF, WebP, SVG — up to 20 MB each, 10 files at a time
              </p>
            </div>

            <%!-- Upload entries / progress --%>
            <div :if={@uploads.media_uploads.entries != []} class="mb-6 space-y-2">
              <div
                :for={entry <- @uploads.media_uploads.entries}
                class="flex items-center gap-3 bg-base-200 rounded-lg px-4 py-2"
              >
                <.icon name="hero-document" class="size-5 text-base-content/50 shrink-0" />
                <div class="flex-1 min-w-0">
                  <p class="text-sm truncate">{entry.client_name}</p>
                  <div class="w-full bg-base-300 rounded-full h-1.5 mt-1">
                    <div
                      class="bg-primary h-1.5 rounded-full transition-all"
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
                  class="btn btn-ghost btn-xs"
                  aria-label="Cancel upload"
                >
                  <.icon name="hero-x-mark" class="size-4" />
                </button>
              </div>

              <%!-- Upload errors --%>
              <p
                :for={err <- upload_errors(@uploads.media_uploads)}
                class="text-error text-sm"
              >
                {upload_error_to_string(err)}
              </p>

              <button type="submit" class="btn btn-primary btn-sm mt-2">
                <.icon name="hero-arrow-up-tray" class="size-4" />
                Upload {length(@uploads.media_uploads.entries)} file(s)
              </button>
            </div>
          </form>

          <%!-- Empty state --%>
          <div :if={@items == []} class="text-center py-16">
            <.icon name="hero-photo" class="size-16 mx-auto text-base-content/20 mb-4" />
            <h2 class="text-lg font-semibold text-base-content/60">No media yet</h2>
            <p class="text-base-content/40 mt-1">Upload images to get started</p>
          </div>

          <%!-- Thumbnail grid --%>
          <div
            :if={@items != []}
            class="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-4 xl:grid-cols-5 gap-3"
          >
            <div
              :for={item <- @items}
              class={[
                "group relative bg-base-200 rounded-lg overflow-hidden cursor-pointer border-2 transition-all aspect-square",
                if(@selected_item && @selected_item.id == item.id,
                  do: "border-primary ring-2 ring-primary/20",
                  else: "border-transparent hover:border-base-content/10"
                )
              ]}
              phx-click="select_item"
              phx-value-id={item.id}
            >
              <img
                src={media_url(item, "thumb")}
                alt={item.alt_text || item.filename}
                class="w-full h-full object-cover"
                loading="lazy"
              />

              <%!-- Status badge overlay --%>
              <div
                :if={item.status != :ready}
                class="absolute top-1.5 right-1.5"
              >
                <span class={["badge badge-xs", status_badge_class(item.status)]}>
                  <span
                    :if={item.status in [:pending, :processing]}
                    class="loading loading-spinner loading-xs mr-1"
                  />
                  {item.status}
                </span>
              </div>

              <%!-- Filename overlay --%>
              <div class="absolute inset-x-0 bottom-0 bg-gradient-to-t from-black/60 to-transparent px-2 py-1.5 opacity-0 group-hover:opacity-100 transition-opacity">
                <p class="text-white text-xs truncate">{item.filename}</p>
              </div>
            </div>
          </div>
        </div>

        <%!-- Detail panel --%>
        <aside
          :if={@selected_item}
          class="w-80 border-l border-base-200 overflow-y-auto shrink-0 bg-base-100"
        >
          <div class="p-5">
            <%!-- Close button --%>
            <div class="flex items-center justify-between mb-4">
              <h3 class="font-semibold text-sm text-base-content/70 uppercase tracking-wide">
                Details
              </h3>
              <button
                phx-click="deselect_item"
                class="btn btn-ghost btn-xs"
                aria-label="Close details"
              >
                <.icon name="hero-x-mark" class="size-4" />
              </button>
            </div>

            <%!-- Preview --%>
            <div class="bg-base-200 rounded-lg overflow-hidden mb-4">
              <img
                src={media_url(@selected_item, "large")}
                alt={@selected_item.alt_text || @selected_item.filename}
                class="w-full h-auto"
              />
            </div>

            <%!-- Metadata --%>
            <div class="space-y-3 mb-4">
              <div>
                <span class="text-xs text-base-content/60 block">Filename</span>
                <span class="text-sm font-medium break-all">{@selected_item.filename}</span>
              </div>

              <div :if={@selected_item.width && @selected_item.height} class="flex gap-4">
                <div>
                  <span class="text-xs text-base-content/60 block">Dimensions</span>
                  <span class="text-sm">{@selected_item.width} x {@selected_item.height}</span>
                </div>
                <div>
                  <span class="text-xs text-base-content/60 block">File size</span>
                  <span class="text-sm">{human_file_size(@selected_item.file_size)}</span>
                </div>
              </div>

              <div :if={!@selected_item.width}>
                <span class="text-xs text-base-content/60 block">File size</span>
                <span class="text-sm">{human_file_size(@selected_item.file_size)}</span>
              </div>

              <div>
                <span class="text-xs text-base-content/60 block">Type</span>
                <span class="text-sm">{@selected_item.mime_type}</span>
              </div>

              <div>
                <span class="text-xs text-base-content/60 block">Status</span>
                <span class={["badge badge-sm", status_badge_class(@selected_item.status)]}>
                  {@selected_item.status}
                </span>
              </div>
            </div>

            <%!-- Alt text --%>
            <div class="mb-4">
              <span class="text-xs text-base-content/60 mb-1 block">Alt Text</span>
              <form phx-change="update_alt_text">
                <input
                  type="text"
                  name="alt_text"
                  value={@selected_item.alt_text || ""}
                  phx-debounce="500"
                  placeholder="Describe this image..."
                  class="input input-sm w-full"
                />
              </form>
            </div>

            <%!-- Actions --%>
            <div class="space-y-2">
              <button
                phx-click="copy_url"
                phx-value-id={@selected_item.id}
                class="btn btn-ghost btn-sm w-full justify-start"
              >
                <.icon name="hero-clipboard-document" class="size-4" /> Copy URL
              </button>

              <button
                phx-click="delete_item"
                phx-value-id={@selected_item.id}
                class="btn btn-ghost btn-sm w-full justify-start text-error hover:bg-error/10"
                data-confirm="Are you sure you want to delete this file? This cannot be undone."
              >
                <.icon name="hero-trash" class="size-4" /> Delete
              </button>
            </div>
          </div>
        </aside>
      </div>
    </Layouts.project>
    """
  end

  defp upload_error_to_string(:too_large), do: "File is too large (max 20 MB)"
  defp upload_error_to_string(:too_many_files), do: "Too many files (max 10)"
  defp upload_error_to_string(:not_accepted), do: "File type not accepted"
  defp upload_error_to_string(err), do: "Error: #{inspect(err)}"
end
