defmodule NexusWeb.Layouts do
  @moduledoc """
  Layout components for the application.

  - `app/1` — Top-level layout for non-project pages (project listing, auth)
  - `project/1` — Sidebar layout for project-scoped pages
  """
  use NexusWeb, :html

  embed_templates "layouts/*"

  # ──────────────────────────────────────────────
  # App Layout (project listing, auth pages)
  # ──────────────────────────────────────────────

  attr :flash, :map, required: true
  attr :current_scope, :map, default: nil
  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <div class="min-h-screen bg-base-300">
      <header class="navbar px-4 sm:px-6 lg:px-8 border-b border-base-200">
        <div class="flex-1">
          <.link navigate={~p"/admin"} class="flex items-center gap-2 text-lg">
            <span class="text-primary text-2xl font-bold">⟐</span>
            <span class="font-medium mb-1" style="font-family: 'Space Grotesk', sans-serif;">
              NEXUS
            </span>
          </.link>
        </div>
        <div class="flex-none">
          <.theme_toggle />
        </div>
      </header>

      <main class="px-4 py-12 sm:px-6 lg:px-8">
        <div class="mx-auto max-w-5xl">
          {render_slot(@inner_block)}
        </div>
      </main>
    </div>

    <.flash_group flash={@flash} />
    """
  end

  # ──────────────────────────────────────────────
  # Project Layout (sidebar + main content)
  # ──────────────────────────────────────────────

  attr :flash, :map, required: true
  attr :project, :map, required: true
  attr :project_role, :atom, default: nil
  attr :sidebar_folders, :list, default: []
  attr :sidebar_pages, :list, default: []
  attr :page_titles, :map, default: %{}
  attr :breadcrumbs, :list, default: []
  attr :active_page_id, :string, default: nil
  attr :creating_content_type, :atom, default: nil

  slot :inner_block, required: true

  def project(assigns) do
    tree_items =
      build_tree_items(assigns.sidebar_folders, assigns.sidebar_pages, assigns.page_titles)

    assigns = assign(assigns, :tree_items, tree_items)

    ~H"""
    <div class="flex h-screen bg-base-300">
      <%!-- Sidebar --%>
      <aside class="w-64 flex flex-col shrink-0 border-r border-base-200">
        <%!-- Project header --%>
        <div class="p-4 border-b border-base-300">
          <.link
            navigate={~p"/admin"}
            class="text-lg hover:text-primary transition-colors"
          >
            <span class="text-primary text-2xl font-bold">⟐</span>
            <span class="font-medium mb-1" style="font-family: 'Space Grotesk', sans-serif;">
              NEXUS
            </span>
          </.link>
          <.link
            navigate={~p"/admin/#{@project.slug}"}
            class="block text-sm text-base-content/60 hover:text-base-content transition-colors mt-0.5 truncate"
          >
            {@project.name}
          </.link>
        </div>

        <%!-- Content tree --%>
        <div class="flex-1 overflow-y-auto p-2">
          <div class="px-2 py-1.5 text-xs font-semibold text-base-content/40 uppercase tracking-wider">
            Content
          </div>
          <div
            id="content-tree"
            phx-hook="ContentTreeSort"
            data-project-id={@project.id}
            class="mt-1"
          >
            <ul
              class="menu menu-sm p-0 sortable-container  w-full "
              data-parent-type="root"
              data-parent-id=""
            >
              <%= if @tree_items == [] && @creating_content_type == nil do %>
                <li class="disabled">
                  <span class="text-xs text-base-content/30">No content yet</span>
                </li>
              <% else %>
                <.tree_item
                  :for={item <- @tree_items}
                  item={item}
                  project_slug={to_string(@project.slug)}
                  active_page_id={@active_page_id}
                />
              <% end %>
              <.inline_create_input
                :if={@creating_content_type != nil}
                type={@creating_content_type}
              />
            </ul>
          </div>
          <button
            type="button"
            phx-click="start_creating_page"
            class="flex items-center gap-1.5 px-3 py-1.5 mt-2 text-xs text-base-content/40 hover:text-base-content hover:bg-base-300 rounded-box transition-colors w-full"
          >
            <.icon name="hero-plus" class="size-3" /> New page
          </button>
          <button
            type="button"
            phx-click="start_creating_folder"
            class="flex items-center gap-1.5 px-3 py-1.5 text-xs text-base-content/40 hover:text-base-content hover:bg-base-300 rounded-box transition-colors w-full"
          >
            <.icon name="hero-plus" class="size-3" /> New folder
          </button>
        </div>

        <%!-- Bottom nav --%>
        <nav class="border-t border-base-300 p-2 space-y-px">
          <.sidebar_nav_link
            href={~p"/admin/#{@project.slug}/members"}
            icon="hero-users"
            label="Members"
          />
          <.sidebar_nav_link
            href={~p"/admin/#{@project.slug}/api-keys"}
            icon="hero-key"
            label="API Keys"
          />
          <.sidebar_nav_link
            href={~p"/admin/#{@project.slug}/settings"}
            icon="hero-cog-6-tooth"
            label="Settings"
          />
        </nav>
      </aside>

      <%!-- Main area --%>
      <div class="flex-1 flex flex-col min-w-0">
        <%!-- Top bar with breadcrumbs --%>
        <header class="h-14 border-b border-base-200 flex items-center px-6 shrink-0">
          <nav class="flex items-center gap-1.5 text-sm min-w-0">
            <.link
              navigate={~p"/admin"}
              class="text-base-content/40 hover:text-base-content shrink-0"
            >
              Projects
            </.link>
            <.icon name="hero-chevron-right-mini" class="size-4 text-base-content/25 shrink-0" />
            <.link
              navigate={~p"/admin/#{@project.slug}"}
              class={[
                "hover:text-base-content truncate",
                if(@breadcrumbs == [],
                  do: "text-base-content font-medium",
                  else: "text-base-content/40"
                )
              ]}
            >
              {@project.name}
            </.link>
            <%= for {{label, path}, idx} <- Enum.with_index(@breadcrumbs) do %>
              <.icon
                name="hero-chevron-right-mini"
                class="size-4 text-base-content/25 shrink-0"
              />
              <%= if idx == length(@breadcrumbs) - 1 do %>
                <span class="text-base-content font-medium truncate">{label}</span>
              <% else %>
                <.link
                  navigate={path}
                  class="text-base-content/40 hover:text-base-content truncate"
                >
                  {label}
                </.link>
              <% end %>
            <% end %>
          </nav>
          <div class="ml-auto flex items-center gap-3 shrink-0">
            <.theme_toggle />
          </div>
        </header>

        <%!-- Page content --%>
        <main class="flex-1 overflow-y-auto">
          {render_slot(@inner_block)}
        </main>
      </div>
    </div>

    <.flash_group flash={@flash} />
    """
  end

  # ──────────────────────────────────────────────
  # Sidebar Tree Components
  # ──────────────────────────────────────────────

  attr :item, :map, required: true
  attr :project_slug, :string, required: true
  attr :active_page_id, :string, default: nil

  defp tree_item(assigns) do
    ~H"""
    <%= if @item.type == :folder do %>
      <li
        id={"tree-item-folder-#{@item.data.id}"}
        class="tree-item w-full pb-1"
        data-type="folder"
        data-id={@item.data.id}
        data-position={@item.data.position || 0}
        data-parent-id={@item.data.parent_id || ""}
      >
        <details open>
          <summary class="group folder-summary ">
            <.icon name="hero-folder" class="size-4 shrink-0 folder-closed" />
            <.icon name="hero-folder-open" class="size-4 shrink-0 folder-open" />
            <span class="truncate font-medium text-sm text-base-content/60">
              {@item.data.name}
            </span>
            <.icon
              name="hero-bars-2"
              class="size-3 text-base-content/30 shrink-0 cursor-grab tree-drag-handle ml-auto"
            />
          </summary>
          <ul
            class="sortable-container menu-dropdown menu-dropdown-show pt-1"
            data-parent-type="folder"
            data-parent-id={@item.data.id}
          >
            <.tree_item
              :for={child <- @item.children}
              item={child}
              project_slug={@project_slug}
              active_page_id={@active_page_id}
            />
          </ul>
        </details>
      </li>
    <% else %>
      <li
        id={"tree-item-page-#{@item.data.id}"}
        class="tree-item w-full pb-1"
        data-type="page"
        data-id={@item.data.id}
        data-position={@item.data.position || 0}
        data-folder-id={@item.data.folder_id || ""}
        data-parent-page-id={@item.data.parent_page_id || ""}
      >
        <%= if @item.children != [] do %>
          <.link
            navigate={~p"/admin/#{@project_slug}/pages/#{@item.data.id}/edit"}
            class={[
              "group",
              if(@active_page_id == @item.data.id,
                do: "bg-primary/10 text-primary font-medium",
                else: "text-base-content/60"
              )
            ]}
          >
            <.icon name="hero-document-text" class="size-4 shrink-0" />
            <span class="truncate text-sm">{@item[:title] || @item.data.slug}</span>
            <span :if={@item.data.status == :published} class="shrink-0">
              <span class="w-1.5 h-1.5 rounded-full bg-success inline-block"></span>
            </span>
            <.icon
              name="hero-bars-2"
              class="size-3 text-base-content/30 shrink-0 cursor-grab tree-drag-handle ml-auto"
            />
          </.link>
          <ul
            class="sortable-container menu-dropdown menu-dropdown-show"
            data-parent-type="page"
            data-parent-id={@item.data.id}
          >
            <.tree_item
              :for={child <- @item.children}
              item={child}
              project_slug={@project_slug}
              active_page_id={@active_page_id}
            />
          </ul>
        <% else %>
          <.link
            navigate={~p"/admin/#{@project_slug}/pages/#{@item.data.id}/edit"}
            class={[
              "group",
              if(@active_page_id == @item.data.id,
                do: "bg-primary/10 text-primary font-medium",
                else: "text-base-content/60"
              )
            ]}
          >
            <.icon name="hero-document-text" class="size-4 shrink-0" />
            <span class="truncate text-sm">{@item[:title] || @item.data.slug}</span>
            <span :if={@item.data.status == :published} class="shrink-0">
              <span class="w-1.5 h-1.5 rounded-full bg-success inline-block"></span>
            </span>
            <.icon
              name="hero-bars-2"
              class="size-3 text-base-content/30 shrink-0 cursor-grab tree-drag-handle ml-auto"
            />
          </.link>
          <ul
            class="sortable-container menu-dropdown menu-dropdown-show"
            data-parent-type="page"
            data-parent-id={@item.data.id}
          >
          </ul>
        <% end %>
      </li>
    <% end %>
    """
  end

  attr :href, :string, required: true
  attr :icon, :string, required: true
  attr :label, :string, required: true

  defp sidebar_nav_link(assigns) do
    ~H"""
    <.link
      navigate={@href}
      class="flex items-center gap-2 px-3 py-2 text-sm rounded-box hover:bg-base-300 text-base-content/60 hover:text-base-content transition-colors"
    >
      <.icon name={@icon} class="size-4" />
      {@label}
    </.link>
    """
  end

  attr :type, :atom, required: true

  defp inline_create_input(assigns) do
    icon = if assigns.type == :folder, do: "hero-folder", else: "hero-document-text"
    assigns = assign(assigns, :icon, icon)

    ~H"""
    <li class="tree-item w-full pb-1" id="inline-create-item">
      <form
        phx-submit="save_inline_content"
        phx-click-away="cancel_inline_create"
        class="flex items-center gap-2 px-2 py-1"
      >
        <input type="hidden" name="type" value={@type} />
        <.icon name={@icon} class="size-4 shrink-0 text-base-content/60" />
        <input
          type="text"
          name="name"
          placeholder={if @type == :folder, do: "Folder name", else: "Page slug"}
          autofocus
          phx-mounted={JS.focus()}
          phx-keydown="cancel_inline_create"
          phx-key="Escape"
          class="input input-xs input-bordered flex-1 bg-base-100"
        />
      </form>
    </li>
    """
  end

  # ──────────────────────────────────────────────
  # Tree Data Builder
  # ──────────────────────────────────────────────

  defp build_tree_items(folders, pages, page_titles) do
    folder_by_parent = Enum.group_by(folders, & &1.parent_id)
    pages_by_folder = Enum.group_by(pages, & &1.folder_id)
    pages_by_parent = Enum.group_by(pages, & &1.parent_page_id)

    build_children_at_level(nil, folder_by_parent, pages_by_folder, pages_by_parent, page_titles)
  end

  defp build_children_at_level(
         parent_id,
         folder_by_parent,
         pages_by_folder,
         pages_by_parent,
         page_titles
       ) do
    folder_items =
      Map.get(folder_by_parent, parent_id, [])
      |> Enum.map(fn folder ->
        children =
          build_children_at_level(
            folder.id,
            folder_by_parent,
            pages_by_folder,
            pages_by_parent,
            page_titles
          )

        %{type: :folder, data: folder, children: children}
      end)

    page_items = build_page_tree(parent_id, nil, pages_by_folder, pages_by_parent, page_titles)

    (folder_items ++ page_items)
    |> Enum.sort_by(fn item -> item.data.position || 0 end)
  end

  defp build_page_tree(folder_id, parent_page_id, pages_by_folder, pages_by_parent, page_titles) do
    pages =
      if parent_page_id do
        Map.get(pages_by_parent, parent_page_id, [])
      else
        Map.get(pages_by_folder, folder_id, [])
        |> Enum.filter(&is_nil(&1.parent_page_id))
      end

    pages
    |> Enum.sort_by(&(&1.position || 0))
    |> Enum.map(fn page ->
      sub_pages =
        build_page_tree(folder_id, page.id, pages_by_folder, pages_by_parent, page_titles)

      %{
        type: :page,
        data: page,
        title: Map.get(page_titles, page.id, to_string(page.slug)),
        children: sub_pages
      }
    end)
  end

  # ──────────────────────────────────────────────
  # Shared Components
  # ──────────────────────────────────────────────

  @doc """
  Shows the flash group with standard titles and content.
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full">
      <div class="absolute w-1/3 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 transition-[left]" />

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end
end
