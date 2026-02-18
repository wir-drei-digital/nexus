defmodule NexusWeb.PageLive.Edit do
  use NexusWeb, :live_view

  on_mount {NexusWeb.LiveUserAuth, :live_user_required}
  on_mount {NexusWeb.ProjectScope, :default}

  @block_types [
    {"Text", "text", "hero-bars-3"},
    {"Heading", "heading", "hero-hashtag"},
    {"Image", "image", "hero-photo"},
    {"Code", "code", "hero-code-bracket"},
    {"Quote", "quote", "hero-chat-bubble-bottom-center-text"},
    {"List", "list", "hero-list-bullet"},
    {"Divider", "divider", "hero-minus"}
  ]

  @impl true
  def mount(%{"id" => page_id}, _session, socket) do
    user = socket.assigns.current_user
    project = socket.assigns.project

    case Ash.get(Nexus.Content.Page, page_id, actor: user) do
      {:ok, page} ->
        locale = project.default_locale
        version = load_current_version(page, locale)
        locales = load_locales(page, user)

        {:ok,
         socket
         |> assign(:page_title, "Edit - #{page.slug}")
         |> assign(:page, page)
         |> assign(:current_locale, locale)
         |> assign(:locales, locales)
         |> assign(:version, version)
         |> assign(:blocks, (version && version.blocks) || [])
         |> assign(:title, (version && version.title) || "")
         |> assign(:meta_description, (version && version.meta_description) || "")
         |> assign(:meta_keywords, (version && Enum.join(version.meta_keywords, ", ")) || "")
         |> assign(:block_types, @block_types)
         |> assign(:saving, false)}

      {:error, _} ->
        {:ok,
         socket
         |> put_flash(:error, "Page not found")
         |> push_navigate(to: ~p"/projects/#{project.slug}/pages")}
    end
  end

  @impl true
  def handle_event("switch_locale", %{"locale" => locale}, socket) do
    version = load_current_version(socket.assigns.page, locale)

    {:noreply,
     socket
     |> assign(:current_locale, locale)
     |> assign(:version, version)
     |> assign(:blocks, (version && version.blocks) || [])
     |> assign(:title, (version && version.title) || "")
     |> assign(:meta_description, (version && version.meta_description) || "")
     |> assign(:meta_keywords, (version && Enum.join(version.meta_keywords, ", ")) || "")}
  end

  @impl true
  def handle_event("add_locale", %{"locale" => locale}, socket) when locale != "" do
    page = socket.assigns.page
    user = socket.assigns.current_user

    case Nexus.Content.PageLocale.create(
           %{page_id: page.id, locale: locale},
           actor: user
         ) do
      {:ok, _} ->
        locales = load_locales(page, user)

        {:noreply,
         socket
         |> assign(:locales, locales)
         |> assign(:current_locale, locale)
         |> assign(:version, nil)
         |> assign(:blocks, [])
         |> assign(:title, "")
         |> assign(:meta_description, "")
         |> assign(:meta_keywords, "")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to add locale")}
    end
  end

  @impl true
  def handle_event("add_block", %{"type" => type}, socket) do
    new_block = build_default_block(type, length(socket.assigns.blocks))
    blocks = socket.assigns.blocks ++ [new_block]
    {:noreply, assign(socket, :blocks, blocks)}
  end

  @impl true
  def handle_event("remove_block", %{"index" => index_str}, socket) do
    index = String.to_integer(index_str)
    blocks = List.delete_at(socket.assigns.blocks, index)
    blocks = reindex_blocks(blocks)
    {:noreply, assign(socket, :blocks, blocks)}
  end

  @impl true
  def handle_event("move_block_up", %{"index" => index_str}, socket) do
    index = String.to_integer(index_str)

    if index > 0 do
      blocks = swap_blocks(socket.assigns.blocks, index, index - 1)
      {:noreply, assign(socket, :blocks, reindex_blocks(blocks))}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("move_block_down", %{"index" => index_str}, socket) do
    index = String.to_integer(index_str)

    if index < length(socket.assigns.blocks) - 1 do
      blocks = swap_blocks(socket.assigns.blocks, index, index + 1)
      {:noreply, assign(socket, :blocks, reindex_blocks(blocks))}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("update_block", %{"index" => index_str} = params, socket) do
    index = String.to_integer(index_str)
    block = Enum.at(socket.assigns.blocks, index)

    updated_data = update_block_data(block, params)
    updated_block = %{block | data: updated_data}
    blocks = List.replace_at(socket.assigns.blocks, index, updated_block)
    {:noreply, assign(socket, :blocks, blocks)}
  end

  @impl true
  def handle_event("update_meta", params, socket) do
    {:noreply,
     socket
     |> assign(:title, Map.get(params, "title", socket.assigns.title))
     |> assign(
       :meta_description,
       Map.get(params, "meta_description", socket.assigns.meta_description)
     )
     |> assign(:meta_keywords, Map.get(params, "meta_keywords", socket.assigns.meta_keywords))}
  end

  @impl true
  def handle_event("save_version", _params, socket) do
    user = socket.assigns.current_user
    page = socket.assigns.page
    locale = socket.assigns.current_locale

    keywords =
      socket.assigns.meta_keywords
      |> String.split(",")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    blocks_data = Enum.map(socket.assigns.blocks, &serialize_block/1)

    case Nexus.Content.PageVersion.create(
           %{
             page_id: page.id,
             locale: locale,
             title: socket.assigns.title,
             meta_description: socket.assigns.meta_description,
             meta_keywords: keywords,
             blocks: blocks_data,
             created_by_id: user.id
           },
           actor: user
         ) do
      {:ok, version} ->
        {:noreply,
         socket
         |> assign(:version, version)
         |> put_flash(:info, "Version #{version.version_number} saved")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to save version")}
    end
  end

  @impl true
  def handle_event("publish", _params, socket) do
    user = socket.assigns.current_user
    page = socket.assigns.page

    with {:ok, page} <- Ash.update(page, %{}, action: :publish, actor: user) do
      {:noreply,
       socket
       |> assign(:page, page)
       |> put_flash(:info, "Page published")}
    else
      {:error, _} -> {:noreply, put_flash(socket, :error, "Failed to publish")}
    end
  end

  @impl true
  def handle_event("unpublish", _params, socket) do
    user = socket.assigns.current_user
    page = socket.assigns.page

    with {:ok, page} <- Ash.update(page, %{}, action: :unpublish, actor: user) do
      {:noreply,
       socket
       |> assign(:page, page)
       |> put_flash(:info, "Page unpublished")}
    else
      {:error, _} -> {:noreply, put_flash(socket, :error, "Failed to unpublish")}
    end
  end

  @impl true
  def handle_event("publish_locale", _params, socket) do
    user = socket.assigns.current_user
    page = socket.assigns.page
    locale = socket.assigns.current_locale
    version = socket.assigns.version

    if version do
      page_locale =
        Enum.find(socket.assigns.locales, fn pl -> pl.locale == locale end)

      if page_locale do
        case Ash.update(page_locale, %{published_version_id: version.id},
               action: :publish_locale,
               actor: user
             ) do
          {:ok, _} ->
            locales = load_locales(page, user)

            {:noreply,
             socket |> assign(:locales, locales) |> put_flash(:info, "Locale published")}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Failed to publish locale")}
        end
      else
        {:noreply, put_flash(socket, :error, "Locale not found")}
      end
    else
      {:noreply, put_flash(socket, :error, "Save a version first")}
    end
  end

  @impl true
  def handle_event("reorder_tree_item", params, socket) do
    NexusWeb.ContentTreeHandlers.handle_event("reorder_tree_item", params, socket)
  end

  defp load_current_version(page, locale) do
    case Nexus.Content.PageVersion.current_for_locale(page.id, locale, authorize?: false) do
      {:ok, version} -> version
      _ -> nil
    end
  end

  defp load_locales(page, user) do
    case Nexus.Content.PageLocale.for_page(page.id, actor: user, load: [:published_version]) do
      {:ok, locales} -> locales
      {:error, _} -> []
    end
  end

  defp build_default_block(type, position) do
    id = Ash.UUID.generate()

    data =
      case type do
        "text" -> %{type: :text, value: %{content: ""}}
        "heading" -> %{type: :heading, value: %{content: "", level: 2}}
        "image" -> %{type: :image, value: %{url: "", alt: "", caption: ""}}
        "code" -> %{type: :code, value: %{content: "", language: ""}}
        "quote" -> %{type: :quote, value: %{content: "", attribution: ""}}
        "list" -> %{type: :list, value: %{style: :unordered, items: [""]}}
        "divider" -> %{type: :divider, value: %{}}
      end

    %{id: id, type: data.type, data: data, position: position}
  end

  defp update_block_data(block, params) do
    case block.type do
      :text ->
        %{type: :text, value: %{content: params["content"] || ""}}

      :heading ->
        %{
          type: :heading,
          value: %{
            content: params["content"] || "",
            level: String.to_integer(params["level"] || "2")
          }
        }

      :image ->
        %{
          type: :image,
          value: %{
            url: params["url"] || "",
            alt: params["alt"] || "",
            caption: params["caption"] || ""
          }
        }

      :code ->
        %{
          type: :code,
          value: %{content: params["content"] || "", language: params["language"] || ""}
        }

      :quote ->
        %{
          type: :quote,
          value: %{content: params["content"] || "", attribution: params["attribution"] || ""}
        }

      :list ->
        items =
          (params["items"] || "")
          |> String.split("\n")
          |> Enum.map(&String.trim/1)
          |> Enum.reject(&(&1 == ""))

        style =
          if params["style"] == "ordered", do: :ordered, else: :unordered

        %{type: :list, value: %{style: style, items: items}}

      :divider ->
        %{type: :divider, value: %{}}
    end
  end

  defp serialize_block(block) do
    %{
      id: block.id || Ash.UUID.generate(),
      type: block.type,
      data: block.data,
      position: block.position
    }
  end

  defp swap_blocks(blocks, i, j) do
    a = Enum.at(blocks, i)
    b = Enum.at(blocks, j)

    blocks
    |> List.replace_at(i, b)
    |> List.replace_at(j, a)
  end

  defp reindex_blocks(blocks) do
    blocks
    |> Enum.with_index()
    |> Enum.map(fn {block, idx} -> %{block | position: idx} end)
  end

  defp block_value(block, key) do
    case block.data do
      %{value: value} when is_map(value) -> Map.get(value, key, "")
      _ -> ""
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.project
      flash={@flash}
      project={@project}
      project_role={@project_role}
      sidebar_directories={@sidebar_directories}
      sidebar_pages={@sidebar_pages}
      active_path={to_string(@page.full_path)}
      breadcrumbs={[
        {"Pages", ~p"/projects/#{@project.slug}/pages"},
        {to_string(@page.slug), nil}
      ]}
    >
      <div class="flex h-full">
        <%!-- Center: Editor --%>
        <div class="flex-1 overflow-y-auto">
          <div class="max-w-3xl mx-auto py-8 px-8">
            <%!-- Locale tabs --%>
            <div class="flex items-center gap-2 mb-8">
              <button
                :for={pl <- @locales}
                phx-click="switch_locale"
                phx-value-locale={pl.locale}
                class={[
                  "px-3 py-1 text-sm rounded-full transition-colors",
                  if(pl.locale == @current_locale,
                    do: "bg-primary text-primary-content",
                    else: "bg-base-200 text-base-content/60 hover:bg-base-300"
                  )
                ]}
              >
                {String.upcase(pl.locale)}
                <span
                  :if={pl.published_version_id}
                  class="inline-block w-1.5 h-1.5 rounded-full bg-success ml-1"
                >
                </span>
              </button>
              <form id="add-locale-form" phx-submit="add_locale" class="flex items-center gap-1">
                <input
                  type="text"
                  name="locale"
                  placeholder="+ locale"
                  class="input input-xs input-bordered w-20 text-xs"
                />
              </form>
            </div>

            <%!-- Title --%>
            <input
              type="text"
              value={@title}
              phx-change="update_meta"
              phx-debounce="300"
              name="title"
              class="w-full text-3xl font-bold bg-transparent border-none focus:outline-none focus:ring-0 placeholder:text-base-content/20 mb-2 p-0"
              placeholder="Page title..."
            />
            <div class="text-sm text-base-content/40 font-mono mb-8">{@page.full_path}</div>

            <%!-- Blocks --%>
            <div class="space-y-4">
              <div
                :for={{block, index} <- Enum.with_index(@blocks)}
                class="group relative"
              >
                <%!-- Block controls (visible on hover) --%>
                <div class="absolute -left-10 top-1 opacity-0 group-hover:opacity-100 transition-opacity flex flex-col gap-0.5">
                  <button
                    phx-click="move_block_up"
                    phx-value-index={index}
                    class="btn btn-ghost btn-xs px-1"
                    disabled={index == 0}
                  >
                    <.icon name="hero-chevron-up" class="size-3" />
                  </button>
                  <button
                    phx-click="move_block_down"
                    phx-value-index={index}
                    class="btn btn-ghost btn-xs px-1"
                    disabled={index == length(@blocks) - 1}
                  >
                    <.icon name="hero-chevron-down" class="size-3" />
                  </button>
                </div>
                <div class="absolute -right-10 top-1 opacity-0 group-hover:opacity-100 transition-opacity">
                  <button
                    phx-click="remove_block"
                    phx-value-index={index}
                    class="btn btn-ghost btn-xs px-1 text-error"
                  >
                    <.icon name="hero-trash" class="size-3" />
                  </button>
                </div>

                <%!-- Block content --%>
                <div class={[
                  "rounded-box transition-colors",
                  "border border-transparent group-hover:border-base-300"
                ]}>
                  <.block_editor block={block} index={index} />
                </div>
              </div>
            </div>

            <%!-- Empty state --%>
            <div
              :if={@blocks == []}
              class="text-center py-16 text-base-content/30"
            >
              <.icon name="hero-document-text" class="size-12 mx-auto mb-3" />
              <p>Add content blocks from the panel on the right</p>
            </div>
          </div>
        </div>

        <%!-- Right sidebar: Settings --%>
        <aside class="w-80 border-l border-base-300 overflow-y-auto shrink-0 bg-base-100">
          <div class="p-5 space-y-6">
            <%!-- Publish section --%>
            <div>
              <h3 class="font-semibold text-sm mb-3 text-base-content/70 uppercase tracking-wide">
                Publish
              </h3>
              <div class="space-y-3">
                <div class="flex items-center justify-between">
                  <span class="text-sm text-base-content/60">Status</span>
                  <span class={[
                    "badge badge-sm",
                    @page.status == :published && "badge-success",
                    @page.status == :draft && "badge-warning",
                    @page.status == :archived && "badge-neutral"
                  ]}>
                    {@page.status}
                  </span>
                </div>
                <div :if={@version} class="flex items-center justify-between">
                  <span class="text-sm text-base-content/60">Version</span>
                  <span class="text-sm font-mono">v{@version.version_number}</span>
                </div>
                <div class="flex gap-2">
                  <button
                    phx-click="save_version"
                    class="btn btn-sm flex-1"
                    phx-disable-with="Saving..."
                  >
                    Save Draft
                  </button>
                  <%= if @page.status == :published do %>
                    <button phx-click="unpublish" class="btn btn-warning btn-sm flex-1">
                      Unpublish
                    </button>
                  <% else %>
                    <button phx-click="publish" class="btn btn-success btn-sm flex-1">
                      Publish
                    </button>
                  <% end %>
                </div>
                <button
                  :if={@version}
                  phx-click="publish_locale"
                  class="btn btn-outline btn-sm w-full"
                >
                  Publish Locale ({String.upcase(@current_locale)})
                </button>
              </div>
            </div>

            <div class="divider my-0"></div>

            <%!-- SEO section --%>
            <div>
              <h3 class="font-semibold text-sm mb-3 text-base-content/70 uppercase tracking-wide">
                SEO Settings
              </h3>
              <div class="space-y-3">
                <div>
                  <div class="flex items-center justify-between mb-1">
                    <label class="text-xs text-base-content/60">Meta Title</label>
                    <span class="text-xs text-base-content/40">
                      {String.length(@title)}/60
                    </span>
                  </div>
                  <input
                    type="text"
                    value={@title}
                    phx-change="update_meta"
                    phx-debounce="300"
                    name="title"
                    class="input input-sm input-bordered w-full"
                    placeholder="Page title for search engines"
                  />
                </div>
                <div>
                  <label class="text-xs text-base-content/60 mb-1 block">URL Slug</label>
                  <div class="input input-sm input-bordered flex items-center w-full text-base-content/40 text-xs font-mono">
                    /{@page.full_path}
                  </div>
                </div>
                <div>
                  <div class="flex items-center justify-between mb-1">
                    <label class="text-xs text-base-content/60">Meta Description</label>
                    <span class="text-xs text-base-content/40">
                      {String.length(@meta_description)}/160
                    </span>
                  </div>
                  <textarea
                    phx-change="update_meta"
                    phx-debounce="300"
                    name="meta_description"
                    class="textarea textarea-bordered textarea-sm w-full"
                    rows="3"
                    placeholder="Brief description for search results"
                  >{@meta_description}</textarea>
                </div>
                <div>
                  <label class="text-xs text-base-content/60 mb-1 block">Keywords</label>
                  <input
                    type="text"
                    value={@meta_keywords}
                    phx-change="update_meta"
                    phx-debounce="300"
                    name="meta_keywords"
                    class="input input-sm input-bordered w-full"
                    placeholder="comma, separated, keywords"
                  />
                </div>
              </div>
            </div>

            <div class="divider my-0"></div>

            <%!-- Block palette --%>
            <div>
              <h3 class="font-semibold text-sm mb-3 text-base-content/70 uppercase tracking-wide">
                Content Blocks
              </h3>
              <div class="grid grid-cols-2 gap-2">
                <button
                  :for={{label, type, icon} <- @block_types}
                  phx-click="add_block"
                  phx-value-type={type}
                  class="flex flex-col items-center gap-1 p-3 rounded-box border border-base-300 hover:bg-base-200 hover:border-primary/30 transition-colors text-base-content/60 hover:text-base-content"
                >
                  <.icon name={icon} class="size-5" />
                  <span class="text-xs">{label}</span>
                </button>
              </div>
            </div>

            <div class="divider my-0"></div>

            <%!-- Quick links --%>
            <div>
              <.link
                navigate={~p"/projects/#{@project.slug}/pages/#{@page.id}/versions"}
                class="flex items-center gap-2 text-sm text-base-content/60 hover:text-base-content"
              >
                <.icon name="hero-clock" class="size-4" /> Version History
              </.link>
            </div>
          </div>
        </aside>
      </div>
    </Layouts.project>
    """
  end

  # ──────────────────────────────────────────────
  # Block Editor Components
  # ──────────────────────────────────────────────

  attr :block, :map, required: true
  attr :index, :integer, required: true

  defp block_editor(%{block: %{type: :text}} = assigns) do
    ~H"""
    <textarea
      phx-blur="update_block"
      phx-value-index={@index}
      name="content"
      class="textarea w-full min-h-[80px] bg-transparent border-none focus:outline-none resize-y text-base leading-relaxed"
      placeholder="Start writing..."
    >{block_value(@block, :content)}</textarea>
    """
  end

  defp block_editor(%{block: %{type: :heading}} = assigns) do
    ~H"""
    <div class="flex items-start gap-2 p-2">
      <select
        phx-change="update_block"
        phx-value-index={@index}
        name="level"
        class="select select-ghost select-sm w-16 text-xs"
      >
        <option :for={l <- 1..6} value={l} selected={block_value(@block, :level) == l}>
          H{l}
        </option>
      </select>
      <input
        type="text"
        phx-blur="update_block"
        phx-value-index={@index}
        name="content"
        value={block_value(@block, :content)}
        class={[
          "flex-1 bg-transparent border-none focus:outline-none focus:ring-0 font-bold",
          heading_size(block_value(@block, :level))
        ]}
        placeholder="Heading..."
      />
    </div>
    """
  end

  defp block_editor(%{block: %{type: :image}} = assigns) do
    ~H"""
    <div class="p-3 space-y-2">
      <div class="flex items-center gap-2 text-xs text-base-content/40 mb-1">
        <.icon name="hero-photo" class="size-3.5" /> Image
      </div>
      <input
        type="text"
        phx-blur="update_block"
        phx-value-index={@index}
        name="url"
        value={block_value(@block, :url)}
        class="input input-sm input-bordered w-full"
        placeholder="Image URL..."
      />
      <div class="flex gap-2">
        <input
          type="text"
          phx-blur="update_block"
          phx-value-index={@index}
          name="alt"
          value={block_value(@block, :alt)}
          class="input input-sm input-bordered flex-1"
          placeholder="Alt text..."
        />
        <input
          type="text"
          phx-blur="update_block"
          phx-value-index={@index}
          name="caption"
          value={block_value(@block, :caption)}
          class="input input-sm input-bordered flex-1"
          placeholder="Caption..."
        />
      </div>
      <div
        :if={block_value(@block, :url) != ""}
        class="rounded-box overflow-hidden bg-base-200 p-2"
      >
        <img
          src={block_value(@block, :url)}
          alt={block_value(@block, :alt)}
          class="max-h-48 mx-auto rounded"
        />
      </div>
    </div>
    """
  end

  defp block_editor(%{block: %{type: :code}} = assigns) do
    ~H"""
    <div class="rounded-box overflow-hidden">
      <div class="flex items-center gap-2 px-3 py-1.5 bg-base-300/50">
        <.icon name="hero-code-bracket" class="size-3.5 text-base-content/40" />
        <input
          type="text"
          phx-blur="update_block"
          phx-value-index={@index}
          name="language"
          value={block_value(@block, :language)}
          class="input input-xs bg-transparent border-none w-24 text-xs text-base-content/60 p-0"
          placeholder="language"
        />
      </div>
      <textarea
        phx-blur="update_block"
        phx-value-index={@index}
        name="content"
        class="textarea w-full font-mono text-sm bg-base-300/30 border-none rounded-none min-h-[120px] resize-y"
        placeholder="// code..."
      >{block_value(@block, :content)}</textarea>
    </div>
    """
  end

  defp block_editor(%{block: %{type: :quote}} = assigns) do
    ~H"""
    <div class="border-l-4 border-primary/30 pl-4 py-2 space-y-2">
      <textarea
        phx-blur="update_block"
        phx-value-index={@index}
        name="content"
        class="textarea w-full bg-transparent border-none italic text-lg leading-relaxed resize-y min-h-[60px]"
        placeholder="Quote text..."
      >{block_value(@block, :content)}</textarea>
      <input
        type="text"
        phx-blur="update_block"
        phx-value-index={@index}
        name="attribution"
        value={block_value(@block, :attribution)}
        class="input input-sm bg-transparent border-none text-base-content/50 text-sm w-full"
        placeholder="— Attribution"
      />
    </div>
    """
  end

  defp block_editor(%{block: %{type: :list}} = assigns) do
    ~H"""
    <div class="p-3 space-y-2">
      <div class="flex items-center gap-2">
        <select
          phx-change="update_block"
          phx-value-index={@index}
          name="style"
          class="select select-ghost select-xs"
        >
          <option value="unordered" selected={block_value(@block, :style) == :unordered}>
            Bullet List
          </option>
          <option value="ordered" selected={block_value(@block, :style) == :ordered}>
            Numbered List
          </option>
        </select>
      </div>
      <textarea
        phx-blur="update_block"
        phx-value-index={@index}
        name="items"
        class="textarea w-full bg-transparent border-none resize-y min-h-[80px]"
        placeholder="One item per line..."
      >{Enum.join(block_value(@block, :items) || [], "\n")}</textarea>
    </div>
    """
  end

  defp block_editor(%{block: %{type: :divider}} = assigns) do
    ~H"""
    <div class="py-4 px-2">
      <hr class="border-base-300" />
    </div>
    """
  end

  defp heading_size(level) when is_binary(level) do
    heading_size(String.to_integer(level))
  end

  defp heading_size(1), do: "text-3xl"
  defp heading_size(2), do: "text-2xl"
  defp heading_size(3), do: "text-xl"
  defp heading_size(4), do: "text-lg"
  defp heading_size(5), do: "text-base"
  defp heading_size(_), do: "text-sm"
end
