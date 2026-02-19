defmodule NexusWeb.PageLive.Edit do
  use NexusWeb, :live_view

  alias Nexus.Content.Templates.{Registry, Renderer, Template}

  on_mount {NexusWeb.LiveUserAuth, :live_user_required}
  on_mount {NexusWeb.ProjectScope, :default}

  @impl true
  def mount(%{"id" => page_id}, _session, socket) do
    user = socket.assigns.current_user
    project = socket.assigns.project

    case Ash.get(Nexus.Content.Page, page_id, actor: user) do
      {:ok, page} ->
        locale = project.default_locale
        version = load_current_version(page, locale)
        locales = load_locales(page, user)
        locale_map = Map.new(locales, &{&1.locale, &1})
        template = Registry.get(page.template_slug) || Registry.get("default")
        template_data = extract_template_data(version, template)
        available_templates = Registry.available_for_project(project.available_templates)

        {:ok,
         socket
         |> assign(:page_title, "Edit - #{page.slug}")
         |> assign(:page, page)
         |> assign(:template, template)
         |> assign(:template_data, template_data)
         |> assign(:available_templates, available_templates)
         |> assign(:current_locale, locale)
         |> assign(:locales, locales)
         |> assign(:locale_map, locale_map)
         |> assign(:version, version)
         |> assign(:content_html, (version && version.content_html) || "")
         |> assign(:title, (version && version.title) || "")
         |> assign(:meta_description, (version && version.meta_description) || "")
         |> assign(:meta_keywords, (version && Enum.join(version.meta_keywords, ", ")) || "")
         |> assign(:save_status, if(version, do: :saved, else: :unsaved))
         |> assign(:auto_save_ref, nil)}

      {:error, _} ->
        {:ok,
         socket
         |> put_flash(:error, "Page not found")
         |> push_navigate(to: ~p"/admin/#{project.slug}")}
    end
  end

  @impl true
  def handle_event("switch_locale", %{"locale" => locale}, socket) do
    socket = cancel_auto_save_timer(socket)
    page = socket.assigns.page
    user = socket.assigns.current_user
    locale_map = socket.assigns.locale_map
    template = socket.assigns.template

    # Create locale if it doesn't exist yet
    {socket, _locale_map} =
      if Map.has_key?(locale_map, locale) do
        {socket, locale_map}
      else
        case Nexus.Content.PageLocale.create(%{page_id: page.id, locale: locale}, actor: user) do
          {:ok, page_locale} ->
            locales = [page_locale | socket.assigns.locales]
            new_map = Map.put(locale_map, locale, page_locale)
            {assign(socket, locales: locales, locale_map: new_map), new_map}

          {:error, _} ->
            {socket, locale_map}
        end
      end

    version = load_current_version(page, locale)
    template_data = extract_template_data(version, template)

    # Push content to each rich_text editor
    push_events =
      Enum.reduce(template.sections, socket, fn section, sock ->
        if section.type == :rich_text do
          key = Atom.to_string(section.key)
          content = Map.get(template_data, key, Template.default_data(template)[key])
          push_event(sock, "tiptap:set_content:#{key}", %{content: content})
        else
          sock
        end
      end)

    {:noreply,
     push_events
     |> assign(:current_locale, locale)
     |> assign(:version, version)
     |> assign(:template_data, template_data)
     |> assign(:content_html, (version && version.content_html) || "")
     |> assign(:title, (version && version.title) || "")
     |> assign(:meta_description, (version && version.meta_description) || "")
     |> assign(:meta_keywords, (version && Enum.join(version.meta_keywords, ", ")) || "")
     |> assign(:save_status, if(version, do: :saved, else: :unsaved))}
  end

  @impl true
  def handle_event("tiptap:change", %{"key" => key, "content" => content}, socket) do
    template_data = Map.put(socket.assigns.template_data, key, content)
    content_html = render_content_html(socket.assigns.template, template_data)

    {:noreply,
     socket
     |> assign(:template_data, template_data)
     |> assign(:content_html, content_html)
     |> assign(:save_status, :unsaved)}
  end

  @impl true
  def handle_event("update_template_field", %{"section" => section_map}, socket)
      when is_map(section_map) do
    template = socket.assigns.template

    template_data =
      Enum.reduce(section_map, socket.assigns.template_data, fn {key, value}, data ->
        section = Template.get_section(template, key)
        coerced = coerce_value(section, value)
        Map.put(data, key, coerced)
      end)

    content_html = render_content_html(template, template_data)

    socket =
      socket
      |> cancel_auto_save_timer()
      |> assign(:template_data, template_data)
      |> assign(:content_html, content_html)
      |> assign(:save_status, :unsaved)

    ref = Process.send_after(self(), :auto_save_meta, 3_000)

    {:noreply, assign(socket, :auto_save_ref, ref)}
  end

  @impl true
  def handle_event("tiptap:save", %{"key" => key, "content" => content}, socket) do
    template_data = Map.put(socket.assigns.template_data, key, content)
    content_html = render_content_html(socket.assigns.template, template_data)

    {:noreply,
     socket
     |> cancel_auto_save_timer()
     |> assign(:template_data, template_data)
     |> assign(:content_html, content_html)
     |> assign(:save_status, :saving)
     |> then(&do_auto_save/1)}
  end

  @impl true
  def handle_event("update_meta", params, socket) do
    socket = cancel_auto_save_timer(socket)

    socket =
      socket
      |> assign(:title, Map.get(params, "title", socket.assigns.title))
      |> assign(
        :meta_description,
        Map.get(params, "meta_description", socket.assigns.meta_description)
      )
      |> assign(:meta_keywords, Map.get(params, "meta_keywords", socket.assigns.meta_keywords))
      |> assign(:save_status, :unsaved)

    ref = Process.send_after(self(), :auto_save_meta, 3_000)

    {:noreply, assign(socket, :auto_save_ref, ref)}
  end

  @impl true
  def handle_event("save_version", _params, socket) do
    user = socket.assigns.current_user
    page = socket.assigns.page
    locale = socket.assigns.current_locale

    keywords = parse_keywords(socket.assigns.meta_keywords)
    content_html = render_content_html(socket.assigns.template, socket.assigns.template_data)

    case Nexus.Content.PageVersion.create(
           %{
             page_id: page.id,
             locale: locale,
             title: socket.assigns.title,
             meta_description: socket.assigns.meta_description,
             meta_keywords: keywords,
             template_data: socket.assigns.template_data,
             content_html: content_html,
             created_by_id: user.id
           },
           actor: user
         ) do
      {:ok, version} ->
        {:noreply,
         socket
         |> assign(:version, version)
         |> assign(:save_status, :saved)
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
            locale_map = Map.new(locales, &{&1.locale, &1})

            {:noreply,
             socket
             |> assign(:locales, locales)
             |> assign(:locale_map, locale_map)
             |> put_flash(:info, "Locale published")}

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
  def handle_event("change_template", %{"template_slug" => slug}, socket) do
    user = socket.assigns.current_user
    page = socket.assigns.page

    case Registry.get(slug) do
      nil ->
        {:noreply, put_flash(socket, :error, "Template not found")}

      new_template ->
        case Ash.update(page, %{template_slug: slug}, action: :update, actor: user) do
          {:ok, updated_page} ->
            # Migrate existing template_data: keep values for sections that exist in both
            old_data = socket.assigns.template_data
            default_data = Template.default_data(new_template)

            new_data =
              Map.new(new_template.sections, fn section ->
                key = Atom.to_string(section.key)
                {key, Map.get(old_data, key) || Map.get(default_data, key)}
              end)

            # Push new content to rich text editors
            socket =
              Enum.reduce(new_template.sections, socket, fn section, sock ->
                if section.type == :rich_text do
                  key = Atom.to_string(section.key)

                  push_event(sock, "tiptap:set_content:#{key}", %{
                    content: Map.get(new_data, key)
                  })
                else
                  sock
                end
              end)

            {:noreply,
             socket
             |> assign(:page, updated_page)
             |> assign(:template, new_template)
             |> assign(:template_data, new_data)
             |> assign(:save_status, :unsaved)
             |> put_flash(:info, "Template changed to #{new_template.label}")}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Failed to change template")}
        end
    end
  end

  @impl true
  def handle_event("tiptap:" <> _, _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event(event, params, socket)
      when event in ~w(reorder_tree_item start_creating_page start_creating_folder cancel_inline_create save_inline_content) do
    NexusWeb.ContentTreeHandlers.handle_event(event, params, socket)
  end

  @impl true
  def handle_info(:auto_save_meta, socket) do
    {:noreply,
     socket
     |> assign(:save_status, :saving)
     |> assign(:auto_save_ref, nil)
     |> then(&do_auto_save/1)}
  end

  defp do_auto_save(socket) do
    user = socket.assigns.current_user
    page = socket.assigns.page
    locale = socket.assigns.current_locale
    keywords = parse_keywords(socket.assigns.meta_keywords)
    content_html = render_content_html(socket.assigns.template, socket.assigns.template_data)

    attrs = %{
      title: socket.assigns.title,
      meta_description: socket.assigns.meta_description,
      meta_keywords: keywords,
      template_data: socket.assigns.template_data,
      content_html: content_html
    }

    case socket.assigns.version do
      nil ->
        # No version yet — create the first one
        create_attrs =
          Map.merge(attrs, %{
            page_id: page.id,
            locale: locale,
            created_by_id: user.id
          })

        case Nexus.Content.PageVersion.create(create_attrs, actor: user) do
          {:ok, version} ->
            socket
            |> assign(:version, version)
            |> assign(:save_status, :saved)

          {:error, _} ->
            assign(socket, :save_status, :error)
        end

      version ->
        case Ash.update(version, attrs, action: :auto_save, actor: user) do
          {:ok, updated} ->
            socket
            |> assign(:version, updated)
            |> assign(:save_status, :saved)

          {:error, _} ->
            assign(socket, :save_status, :error)
        end
    end
  end

  defp cancel_auto_save_timer(socket) do
    if ref = socket.assigns.auto_save_ref do
      Process.cancel_timer(ref)
    end

    assign(socket, :auto_save_ref, nil)
  end

  defp parse_keywords(str) do
    str
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
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

  defp extract_template_data(nil, template), do: Template.default_data(template)

  defp extract_template_data(version, template) do
    case version.template_data do
      data when is_map(data) and map_size(data) > 0 -> data
      _ -> Template.default_data(template)
    end
  end

  defp render_content_html(template, template_data) do
    Renderer.render(template.slug, template_data)
  end

  defp coerce_value(nil, value), do: value
  defp coerce_value(%{type: :number}, ""), do: nil

  defp coerce_value(%{type: :number}, value) when is_binary(value) do
    case Float.parse(value) do
      {num, ""} -> num
      {num, _} -> num
      :error -> nil
    end
  end

  defp coerce_value(%{type: :toggle}, value) when is_binary(value), do: value == "true"
  defp coerce_value(%{type: :toggle}, value) when is_boolean(value), do: value
  defp coerce_value(_section, value), do: value

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.project
      flash={@flash}
      project={@project}
      project_role={@project_role}
      sidebar_folders={@sidebar_folders}
      sidebar_pages={@sidebar_pages}
      creating_content_type={@creating_content_type}
      active_path={to_string(@page.full_path)}
      breadcrumbs={[{to_string(@page.slug), nil}]}
    >
      <div class="flex h-full">
        <%!-- Center: Editor --%>
        <div class="flex-1 overflow-y-auto">
          <div class="max-w-3xl mx-auto py-8 px-8">
            <%!-- Locale tabs --%>
            <div class="flex items-center gap-1.5 mb-8 flex-wrap">
              <.locale_button
                :for={loc <- @project.available_locales}
                locale={loc}
                page_locale={@locale_map[loc]}
                is_active={loc == @current_locale}
              />
            </div>

            <%!-- Title --%>
            <form phx-change="update_meta" class="pb-4">
              <input
                type="text"
                value={@title}
                phx-debounce="300"
                name="title"
                class="w-full text-3xl font-bold bg-transparent border-none focus:outline-none focus:ring-0 placeholder:text-base-content/20 mb-2 p-0"
                placeholder="Page title..."
              />
            </form>

            <%!-- Template sections --%>
            <form phx-change="update_template_field" class="space-y-6">
              <.template_section
                :for={section <- @template.sections}
                section={section}
                value={Map.get(@template_data, Atom.to_string(section.key))}
              />
            </form>
          </div>
        </div>

        <%!-- Right sidebar: Settings --%>
        <aside class="w-80 border-l border-base-200 overflow-y-auto shrink-0">
          <%!-- Publish section --%>
          <div class="p-5 border-b border-base-200">
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
              <%!-- Save status indicator --%>
              <div class="flex items-center gap-1.5 text-sm">
                <.save_status_indicator status={@save_status} />
              </div>

              <div class="flex gap-2">
                <.button
                  phx-click="save_version"
                  class="btn btn-sm flex-1"
                  phx-disable-with="Saving..."
                >
                  Save as Version
                </.button>
                <%= if @page.status == :published do %>
                  <.button phx-click="unpublish" class="btn btn-warning btn-sm flex-1">
                    Unpublish
                  </.button>
                <% else %>
                  <.button phx-click="publish" class="btn btn-success btn-sm flex-1">
                    Publish
                  </.button>
                <% end %>
              </div>
              <.button
                :if={@version}
                phx-click="publish_locale"
                class="btn btn-ghost btn-sm w-full border border-base-content/20"
              >
                Publish Locale ({String.upcase(@current_locale)})
              </.button>
            </div>
          </div>

          <%!-- SEO section --%>
          <div class="p-5 border-b border-base-200">
            <h3 class="font-semibold text-sm mb-3 text-base-content/70 uppercase tracking-wide">
              SEO Settings
            </h3>
            <.form for={%{}} phx-change="update_meta" class="space-y-3">
              <div>
                <div class="flex items-center justify-between mb-1">
                  <span class="text-xs text-base-content/60">Meta Title</span>
                  <span class="text-xs text-base-content/40">
                    {String.length(@title)}/60
                  </span>
                </div>
                <.input
                  type="text"
                  name="title"
                  value={@title}
                  phx-debounce="300"
                  class="input input-sm w-full"
                  placeholder="Page title for search engines"
                />
              </div>
              <div>
                <span class="text-xs text-base-content/60 mb-1 block">URL Slug</span>
                <div class="input input-sm flex items-center w-full text-base-content/40 text-xs font-mono">
                  /{@page.full_path}
                </div>
              </div>
              <div>
                <div class="flex items-center justify-between mb-1">
                  <span class="text-xs text-base-content/60">Meta Description</span>
                  <span class="text-xs text-base-content/40">
                    {String.length(@meta_description)}/160
                  </span>
                </div>
                <.input
                  type="textarea"
                  name="meta_description"
                  value={@meta_description}
                  phx-debounce="300"
                  class="textarea textarea-sm w-full"
                  rows="3"
                  placeholder="Brief description for search results"
                />
              </div>
              <div>
                <span class="text-xs text-base-content/60 mb-1 block">Keywords</span>
                <.input
                  type="text"
                  name="meta_keywords"
                  value={@meta_keywords}
                  phx-debounce="300"
                  class="input input-sm w-full"
                  placeholder="comma, separated, keywords"
                />
              </div>
            </.form>
          </div>

          <%!-- Page Settings section --%>
          <div class="p-5 border-b border-base-200">
            <h3 class="font-semibold text-sm mb-3 text-base-content/70 uppercase tracking-wide">
              Page Settings
            </h3>
            <div class="space-y-3">
              <form phx-change="change_template">
                <span class="text-xs text-base-content/60 mb-1 block">Template</span>
                <select
                  name="template_slug"
                  class="select select-sm select-bordered w-full"
                >
                  <option
                    :for={t <- @available_templates}
                    value={t.slug}
                    selected={t.slug == @template.slug}
                  >
                    {t.label}
                  </option>
                </select>
              </form>
              <p :if={@template.description} class="text-xs text-base-content/40">
                {@template.description}
              </p>
              <div class="text-xs text-base-content/40">
                {length(@template.sections)} {if length(@template.sections) == 1,
                  do: "section",
                  else: "sections"}: {Enum.map_join(@template.sections, ", ", & &1.label)}
              </div>
            </div>
          </div>

          <%!-- Quick links --%>
          <div class="p-5">
            <.link
              navigate={~p"/admin/#{@project.slug}/pages/#{@page.id}/versions"}
              class="flex items-center gap-2 text-sm text-base-content/60 hover:text-base-content"
            >
              <.icon name="hero-clock" class="size-4" /> Version History
            </.link>
          </div>
        </aside>
      </div>
    </Layouts.project>
    """
  end

  # Section rendering components

  attr :section, :any, required: true
  attr :value, :any, default: nil

  defp template_section(%{section: %{type: :rich_text}} = assigns) do
    key = Atom.to_string(assigns.section.key)
    assigns = assign(assigns, :key, key)

    ~H"""
    <div>
      <label
        :if={@section.label != "Body"}
        class="text-xs font-medium text-base-content/60 mb-1 block"
      >
        {@section.label}
        <span :if={@section.required} class="text-error">*</span>
      </label>
      <TiptapPhoenix.Component.tiptap_editor
        id={"tiptap-editor-#{@key}"}
        content={@value}
        section_key={@key}
      />
    </div>
    """
  end

  defp template_section(%{section: %{type: :text}} = assigns) do
    key = Atom.to_string(assigns.section.key)
    assigns = assign(assigns, :key, key)

    ~H"""
    <div>
      <label class="text-xs font-medium text-base-content/60 mb-1 block">
        {@section.label}
        <span :if={@section.required} class="text-error">*</span>
      </label>
      <input
        type="text"
        value={@value || ""}
        phx-debounce="300"
        name={"section[#{@key}]"}
        class="input input-bordered w-full"
        placeholder={@section.label}
      />
    </div>
    """
  end

  defp template_section(%{section: %{type: :textarea}} = assigns) do
    key = Atom.to_string(assigns.section.key)
    assigns = assign(assigns, :key, key)

    ~H"""
    <div>
      <label class="text-xs font-medium text-base-content/60 mb-1 block">
        {@section.label}
        <span :if={@section.required} class="text-error">*</span>
      </label>
      <textarea
        phx-debounce="300"
        name={"section[#{@key}]"}
        class="textarea textarea-bordered w-full"
        rows="4"
        placeholder={@section.label}
      >{@value || ""}</textarea>
    </div>
    """
  end

  defp template_section(%{section: %{type: :image}} = assigns) do
    key = Atom.to_string(assigns.section.key)
    assigns = assign(assigns, :key, key)

    ~H"""
    <div>
      <label class="text-xs font-medium text-base-content/60 mb-1 block">
        {@section.label}
        <span :if={@section.required} class="text-error">*</span>
      </label>
      <input
        type="url"
        value={@value || ""}
        phx-debounce="300"
        name={"section[#{@key}]"}
        class="input input-bordered w-full"
        placeholder="https://example.com/image.jpg"
      />
      <img
        :if={@value && @value != ""}
        src={@value}
        class="mt-2 max-h-48 rounded-box object-cover"
      />
    </div>
    """
  end

  defp template_section(%{section: %{type: :url}} = assigns) do
    key = Atom.to_string(assigns.section.key)
    assigns = assign(assigns, :key, key)

    ~H"""
    <div>
      <label class="text-xs font-medium text-base-content/60 mb-1 block">
        {@section.label}
        <span :if={@section.required} class="text-error">*</span>
      </label>
      <input
        type="url"
        value={@value || ""}
        phx-debounce="300"
        name={"section[#{@key}]"}
        class="input input-bordered w-full"
        placeholder="https://..."
      />
    </div>
    """
  end

  defp template_section(%{section: %{type: :number}} = assigns) do
    key = Atom.to_string(assigns.section.key)
    assigns = assign(assigns, :key, key)

    ~H"""
    <div>
      <label class="text-xs font-medium text-base-content/60 mb-1 block">
        {@section.label}
        <span :if={@section.required} class="text-error">*</span>
      </label>
      <input
        type="number"
        value={@value}
        phx-debounce="300"
        name={"section[#{@key}]"}
        class="input input-bordered w-full"
      />
    </div>
    """
  end

  defp template_section(%{section: %{type: :select}} = assigns) do
    key = Atom.to_string(assigns.section.key)
    options = Map.get(assigns.section.constraints, :options, [])
    assigns = assign(assigns, key: key, options: options)

    ~H"""
    <div>
      <label class="text-xs font-medium text-base-content/60 mb-1 block">
        {@section.label}
        <span :if={@section.required} class="text-error">*</span>
      </label>
      <select
        name={"section[#{@key}]"}
        class="select select-bordered w-full"
      >
        <option value="">Select...</option>
        <option :for={opt <- @options} value={opt} selected={@value == opt}>{opt}</option>
      </select>
    </div>
    """
  end

  defp template_section(%{section: %{type: :toggle}} = assigns) do
    key = Atom.to_string(assigns.section.key)
    assigns = assign(assigns, :key, key)

    ~H"""
    <div class="flex items-center gap-3">
      <input type="hidden" name={"section[#{@key}]"} value="false" />
      <input
        type="checkbox"
        name={"section[#{@key}]"}
        value="true"
        checked={@value == true}
        class="toggle toggle-primary"
      />
      <label class="text-sm text-base-content/70">{@section.label}</label>
    </div>
    """
  end

  defp save_status_indicator(%{status: :saving} = assigns) do
    ~H"""
    <span class="loading loading-spinner loading-xs text-base-content/50"></span>
    <span class="text-base-content/50">Saving...</span>
    """
  end

  defp save_status_indicator(%{status: :saved} = assigns) do
    ~H"""
    <.icon name="hero-check-circle-mini" class="size-4 text-success" />
    <span class="text-success">Saved</span>
    """
  end

  defp save_status_indicator(%{status: :error} = assigns) do
    ~H"""
    <.icon name="hero-exclamation-circle-mini" class="size-4 text-error" />
    <span class="text-error">Save failed</span>
    """
  end

  defp save_status_indicator(%{status: :unsaved} = assigns) do
    ~H"""
    <.icon name="hero-pencil-mini" class="size-4 text-base-content/40" />
    <span class="text-base-content/40">Unsaved changes</span>
    """
  end

  attr :locale, :string, required: true
  attr :page_locale, :any, default: nil
  attr :is_active, :boolean, default: false

  defp locale_button(assigns) do
    has_content = assigns.page_locale != nil
    is_published = has_content && assigns.page_locale.published_version_id != nil
    assigns = assign(assigns, has_content: has_content, is_published: is_published)

    ~H"""
    <button
      phx-click="switch_locale"
      phx-value-locale={@locale}
      class={[
        "px-3 py-1 text-sm rounded-full transition-colors inline-flex items-center gap-1.5",
        @is_active && "bg-primary text-primary-content",
        !@is_active && @has_content && "bg-base-200 text-base-content/70 hover:bg-base-300",
        !@is_active && !@has_content &&
          "bg-transparent text-base-content/40 border border-dashed border-base-content/20 hover:border-base-content/40 hover:text-base-content/60"
      ]}
    >
      {String.upcase(@locale)}
      <span
        :if={@is_published}
        class="inline-block w-1.5 h-1.5 rounded-full bg-success"
        title="Published"
      >
      </span>
      <span
        :if={!@has_content}
        class="inline-block w-1.5 h-1.5 rounded-full bg-warning"
        title="Missing content"
      >
      </span>
    </button>
    """
  end
end
