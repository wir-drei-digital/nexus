defmodule NexusWeb.PageLive.Edit do
  use NexusWeb, :live_view

  alias Nexus.Content.Templates.{Field, Group, Registry, Renderer, Template}

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
         |> assign(:auto_save_ref, nil)
         |> assign(:seo_generating, false)
         |> assign(:refining_keys, [])
         |> assign(:refine_dialog, nil)
         |> assign(:copy_source_locale, default_copy_source(project, locale))
         |> assign(:auto_translate, true)
         |> assign(:copying_content, false)
         |> assign(:show_copy_confirm, false)}

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
    socket =
      if Map.has_key?(locale_map, locale) do
        socket
      else
        case Nexus.Content.PageLocale.create(%{page_id: page.id, locale: locale}, actor: user) do
          {:ok, page_locale} ->
            locales = [page_locale | socket.assigns.locales]
            new_map = Map.put(locale_map, locale, page_locale)
            assign(socket, locales: locales, locale_map: new_map)

          {:error, _} ->
            socket
        end
      end

    version = load_current_version(page, locale)
    template_data = extract_template_data(version, template)

    socket = push_rich_text_content(socket, template, template_data)

    {:noreply,
     socket
     |> assign(:current_locale, locale)
     |> assign(:version, version)
     |> assign(:template_data, template_data)
     |> assign(:content_html, (version && version.content_html) || "")
     |> assign(:title, (version && version.title) || "")
     |> assign(:meta_description, (version && version.meta_description) || "")
     |> assign(:meta_keywords, (version && Enum.join(version.meta_keywords, ", ")) || "")
     |> assign(:save_status, if(version, do: :saved, else: :unsaved))
     |> assign(:copy_source_locale, default_copy_source(socket.assigns.project, locale))
     |> assign(:show_copy_confirm, false)
     |> assign(:copying_content, false)}
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
  def handle_event("update_template_field", %{"field" => field_map}, socket)
      when is_map(field_map) do
    template = socket.assigns.template

    template_data =
      Enum.reduce(field_map, socket.assigns.template_data, fn {key, value}, data ->
        field = Template.get_field(template, key)
        coerced = coerce_value(field, value)
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

    new_title = Map.get(params, "title", socket.assigns.title)

    socket =
      socket
      |> assign(:title, new_title)
      |> assign(
        :meta_description,
        Map.get(params, "meta_description", socket.assigns.meta_description)
      )
      |> assign(:meta_keywords, Map.get(params, "meta_keywords", socket.assigns.meta_keywords))
      |> assign(:save_status, :unsaved)
      |> maybe_update_slug(new_title)
      |> update(:page_titles, &Map.put(&1, socket.assigns.page.id, new_title))

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
            # Migrate existing template_data: keep values for fields that exist in both
            old_data = socket.assigns.template_data
            default_data = Template.default_data(new_template)

            new_data =
              Map.new(Template.all_fields(new_template), fn field ->
                key = Atom.to_string(field.key)
                {key, Map.get(old_data, key) || Map.get(default_data, key)}
              end)

            socket = push_rich_text_content(socket, new_template, new_data)

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
  def handle_event("update_copy_source", %{"copy_source_locale" => locale}, socket) do
    {:noreply, assign(socket, :copy_source_locale, locale)}
  end

  @impl true
  def handle_event("toggle_auto_translate", _params, socket) do
    {:noreply, update(socket, :auto_translate, &(!&1))}
  end

  @impl true
  def handle_event("copy_content", _params, socket) do
    if socket.assigns.version != nil do
      {:noreply, assign(socket, :show_copy_confirm, true)}
    else
      {:noreply, do_copy_content(socket)}
    end
  end

  @impl true
  def handle_event("confirm_copy_content", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_copy_confirm, false)
     |> do_copy_content()}
  end

  @impl true
  def handle_event("cancel_copy", _params, socket) do
    {:noreply, assign(socket, :show_copy_confirm, false)}
  end

  @impl true
  def handle_event("tiptap:" <> _, _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("generate_seo", _params, socket) do
    title = socket.assigns.title
    template_data = socket.assigns.template_data

    {:noreply,
     socket
     |> assign(:seo_generating, true)
     |> start_async(:generate_seo, fn ->
       Nexus.AI.Assistant.generate_seo(title, Jason.encode!(template_data))
     end)}
  end

  @impl true
  def handle_event("open_refine_dialog", %{"key" => key}, socket) do
    field = Template.get_field(socket.assigns.template, key)
    label = if field, do: field.label, else: key
    field_type = if field, do: field.type, else: :rich_text

    {:noreply, assign(socket, :refine_dialog, %{key: key, label: label, field_type: field_type})}
  end

  @impl true
  def handle_event("close_refine_dialog", _params, socket) do
    {:noreply, assign(socket, :refine_dialog, nil)}
  end

  @impl true
  def handle_event("refine_content", %{"key" => key, "instructions" => instructions}, socket) do
    if key in socket.assigns.refining_keys do
      {:noreply, assign(socket, :refine_dialog, nil)}
    else
      content = Map.get(socket.assigns.template_data, key)
      template = socket.assigns.template
      field = Template.get_field(template, key)
      field_label = if field, do: field.label, else: key
      field_type = if field, do: field.type, else: :rich_text

      content_str =
        case field_type do
          :rich_text when is_map(content) -> Jason.encode!(content)
          :rich_text -> Jason.encode!(Nexus.AI.ProseMirror.default_doc())
          _ -> to_string(content || "")
        end

      context = build_page_context(template, socket.assigns.template_data)

      {:noreply,
       socket
       |> assign(:refine_dialog, nil)
       |> update(:refining_keys, &[key | &1])
       |> start_async({:refine_content, key}, fn ->
         case Nexus.AI.Assistant.refine_content(content_str, instructions, context, field_label) do
           {:ok, markdown} when field_type == :rich_text ->
             case Nexus.AI.ProseMirror.from_markdown(markdown) do
               {:ok, doc} -> {:rich_text, doc}
               {:error, reason} -> {:error, "Failed to parse refined content: #{inspect(reason)}"}
             end

           {:ok, markdown} ->
             {:plain_text, String.trim(markdown)}

           {:error, reason} ->
             {:error, reason}
         end
       end)}
    end
  end

  @impl true
  def handle_event(event, params, socket)
      when event in ~w(reorder_tree_item start_creating_page start_creating_folder cancel_inline_create save_inline_content) do
    NexusWeb.ContentTreeHandlers.handle_event(event, params, socket)
  end

  @impl true
  def handle_async(:generate_seo, {:ok, {:ok, result}}, socket) do
    ref = Process.send_after(self(), :auto_save_meta, 500)

    {:noreply,
     socket
     |> cancel_auto_save_timer()
     |> assign(:seo_generating, false)
     |> assign(:meta_description, result["meta_description"])
     |> assign(:meta_keywords, Enum.join(result["meta_keywords"] || [], ", "))
     |> assign(:save_status, :unsaved)
     |> assign(:auto_save_ref, ref)
     |> put_flash(:info, "SEO generated successfully")}
  end

  @impl true
  def handle_async(:generate_seo, {:ok, {:error, reason}}, socket) do
    {:noreply,
     socket
     |> assign(:seo_generating, false)
     |> put_flash(:error, "Failed to generate SEO: #{inspect(reason)}")}
  end

  @impl true
  def handle_async(:generate_seo, {:exit, _reason}, socket) do
    {:noreply,
     socket
     |> assign(:seo_generating, false)
     |> put_flash(:error, "SEO generation failed unexpectedly")}
  end

  @impl true
  def handle_async({:refine_content, key}, {:ok, {:rich_text, prosemirror_doc}}, socket) do
    socket = cancel_auto_save_timer(socket)
    template_data = Map.put(socket.assigns.template_data, key, prosemirror_doc)
    content_html = render_content_html(socket.assigns.template, template_data)
    ref = Process.send_after(self(), :auto_save_meta, 500)

    {:noreply,
     socket
     |> update(:refining_keys, &List.delete(&1, key))
     |> assign(:template_data, template_data)
     |> assign(:content_html, content_html)
     |> assign(:save_status, :unsaved)
     |> assign(:auto_save_ref, ref)
     |> push_event("tiptap:set_content:#{key}", %{content: prosemirror_doc})}
  end

  @impl true
  def handle_async({:refine_content, key}, {:ok, {:plain_text, text}}, socket) do
    socket = cancel_auto_save_timer(socket)
    template_data = Map.put(socket.assigns.template_data, key, text)
    content_html = render_content_html(socket.assigns.template, template_data)
    ref = Process.send_after(self(), :auto_save_meta, 500)

    {:noreply,
     socket
     |> update(:refining_keys, &List.delete(&1, key))
     |> assign(:template_data, template_data)
     |> assign(:content_html, content_html)
     |> assign(:save_status, :unsaved)
     |> assign(:auto_save_ref, ref)}
  end

  @impl true
  def handle_async({:refine_content, key}, {:ok, {:error, reason}}, socket) do
    {:noreply,
     socket
     |> update(:refining_keys, &List.delete(&1, key))
     |> put_flash(:error, "Failed to refine content: #{inspect(reason)}")}
  end

  @impl true
  def handle_async({:refine_content, key}, {:exit, _reason}, socket) do
    {:noreply,
     socket
     |> update(:refining_keys, &List.delete(&1, key))
     |> put_flash(:error, "Content refinement failed unexpectedly")}
  end

  @impl true
  def handle_async(:copy_translate, {:ok, {:ok, translated, direct_template, seo_data}}, socket) do
    socket = cancel_auto_save_timer(socket)
    template = socket.assigns.template

    translated_template =
      Map.take(translated, Enum.map(Template.all_fields(template), &Atom.to_string(&1.key)))

    new_template_data = Map.merge(direct_template, translated_template)

    new_title = translated["title"] || seo_data.title
    new_meta_desc = translated["meta_description"] || seo_data.meta_description

    socket = push_rich_text_content(socket, template, new_template_data)

    ref = Process.send_after(self(), :auto_save_meta, 500)

    {:noreply,
     socket
     |> assign(:copying_content, false)
     |> assign(:template_data, new_template_data)
     |> assign(:content_html, render_content_html(template, new_template_data))
     |> assign(:title, new_title)
     |> assign(:meta_description, new_meta_desc)
     |> assign(:meta_keywords, Enum.join(seo_data.meta_keywords, ", "))
     |> assign(:save_status, :unsaved)
     |> assign(:auto_save_ref, ref)
     |> put_flash(
       :info,
       "Content translated from #{String.upcase(socket.assigns.copy_source_locale)}"
     )}
  end

  @impl true
  def handle_async(:copy_translate, {:ok, {:error, reason}}, socket) do
    {:noreply,
     socket
     |> assign(:copying_content, false)
     |> put_flash(:error, "Translation failed: #{inspect(reason)}")}
  end

  @impl true
  def handle_async(:copy_translate, {:exit, _reason}, socket) do
    {:noreply,
     socket
     |> assign(:copying_content, false)
     |> put_flash(:error, "Translation failed unexpectedly")}
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

  defp maybe_update_slug(socket, title) do
    new_slug = slugify(title)
    page = socket.assigns.page

    if new_slug != "" && new_slug != to_string(page.slug) do
      case Ash.update(page, %{slug: new_slug},
             action: :update,
             actor: socket.assigns.current_user
           ) do
        {:ok, updated_page} -> assign(socket, :page, updated_page)
        {:error, _} -> socket
      end
    else
      socket
    end
  end

  defp slugify(title) when is_binary(title) do
    title
    |> String.downcase()
    |> String.replace(~r/[^\w\s-]/u, "")
    |> String.replace(~r/[\s_]+/, "-")
    |> String.replace(~r/-+/, "-")
    |> String.trim("-")
  end

  defp slugify(_), do: ""

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

  defp build_page_context(template, template_data) do
    Template.all_fields(template)
    |> Enum.map(fn field ->
      key = Atom.to_string(field.key)
      value = Map.get(template_data, key)

      text =
        case field.type do
          :rich_text -> Nexus.AI.ProseMirror.extract_text(value)
          type when type in [:text, :textarea] -> to_string(value || "")
          _ -> ""
        end
        |> String.trim()

      if text != "", do: "### #{field.label}\n#{text}", else: nil
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n\n")
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

  defp push_rich_text_content(socket, template, template_data) do
    Enum.reduce(Template.all_fields(template), socket, fn field, sock ->
      if field.type == :rich_text do
        key = Atom.to_string(field.key)
        content = Map.get(template_data, key, Template.default_data(template)[key])
        push_event(sock, "tiptap:set_content:#{key}", %{content: content})
      else
        sock
      end
    end)
  end

  defp default_copy_source(project, current_locale) do
    if project.default_locale != current_locale do
      project.default_locale
    else
      project.available_locales
      |> Enum.find(&(&1 != current_locale))
    end
  end

  defp locale_display_name(code) do
    %{
      "en" => "English",
      "de" => "German",
      "fr" => "French",
      "es" => "Spanish",
      "it" => "Italian",
      "pt" => "Portuguese",
      "nl" => "Dutch",
      "pl" => "Polish",
      "ru" => "Russian",
      "zh" => "Chinese",
      "ja" => "Japanese",
      "ko" => "Korean",
      "ar" => "Arabic"
    }
    |> Map.get(code, String.upcase(code))
  end

  defp do_copy_content(socket) do
    source_locale = socket.assigns.copy_source_locale
    page = socket.assigns.page
    template = socket.assigns.template

    source_version = load_current_version(page, source_locale)

    if source_version == nil do
      put_flash(socket, :error, "No content found for #{String.upcase(source_locale)}")
    else
      source_template_data = extract_template_data(source_version, template)

      field_types =
        Template.all_fields(template)
        |> Map.new(fn field -> {Atom.to_string(field.key), field.type} end)

      seo_data = %{
        title: source_version.title || "",
        meta_description: source_version.meta_description || "",
        meta_keywords: source_version.meta_keywords || []
      }

      if socket.assigns.auto_translate do
        do_copy_with_translation(
          socket,
          source_template_data,
          seo_data,
          field_types,
          source_locale
        )
      else
        do_copy_without_translation(socket, source_template_data, seo_data, template)
      end
    end
  end

  defp do_copy_with_translation(
         socket,
         source_template_data,
         seo_data,
         field_types,
         source_locale
       ) do
    target_locale = socket.assigns.current_locale

    {translatable_template, direct_template} =
      Nexus.AI.Helpers.classify_fields(source_template_data, field_types)

    seo_translatable = %{
      "title" => seo_data.title,
      "meta_description" => seo_data.meta_description
    }

    seo_field_types = %{
      "title" => :text,
      "meta_description" => :textarea
    }

    all_translatable = Map.merge(translatable_template, seo_translatable)
    all_field_types = Map.merge(field_types, seo_field_types)

    socket
    |> assign(:copying_content, true)
    |> start_async(:copy_translate, fn ->
      case Nexus.AI.Helpers.translate_content_impl(
             all_translatable,
             source_locale,
             target_locale,
             all_field_types
           ) do
        {:ok, translated} ->
          {:ok, translated, direct_template, seo_data}

        {:error, reason} ->
          {:error, reason}
      end
    end)
  end

  defp do_copy_without_translation(socket, source_template_data, seo_data, template) do
    socket = cancel_auto_save_timer(socket)

    socket = push_rich_text_content(socket, template, source_template_data)

    ref = Process.send_after(self(), :auto_save_meta, 500)

    socket
    |> assign(:template_data, source_template_data)
    |> assign(:content_html, render_content_html(template, source_template_data))
    |> assign(:title, seo_data.title)
    |> assign(:meta_description, seo_data.meta_description)
    |> assign(:meta_keywords, Enum.join(seo_data.meta_keywords, ", "))
    |> assign(:save_status, :unsaved)
    |> assign(:auto_save_ref, ref)
    |> put_flash(:info, "Content copied from #{String.upcase(socket.assigns.copy_source_locale)}")
  end

  defp coerce_value(nil, value), do: value
  defp coerce_value(%Field{type: :number}, ""), do: nil

  defp coerce_value(%Field{type: :number}, value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} ->
        int

      _ ->
        case Float.parse(value) do
          {num, ""} -> num
          _ -> nil
        end
    end
  end

  defp coerce_value(%Field{type: :toggle}, value) when is_binary(value), do: value == "true"
  defp coerce_value(%Field{type: :toggle}, value) when is_boolean(value), do: value
  defp coerce_value(%Field{}, value), do: value

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
      active_page_id={@page.id}
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

            <%!-- Template fields --%>
            <form phx-change="update_template_field" class="space-y-6">
              <.template_item
                :for={item <- @template.fields}
                item={item}
                template_data={@template_data}
                refining_keys={@refining_keys}
              />
            </form>
          </div>
        </div>

        <%!-- Right sidebar: Settings --%>
        <aside class="w-80 border-l border-base-200 overflow-y-auto shrink-0">
          <%!-- Publish --%>
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

          <%!-- SEO --%>
          <div class="p-5 border-b border-base-200">
            <h3 class="font-semibold text-sm mb-3 text-base-content/70 uppercase tracking-wide">
              SEO Settings
            </h3>
            <.form for={%{}} phx-change="update_meta" class="space-y-3">
              <div>
                <span class="text-xs text-base-content/60 mb-1 block">URL Slug</span>
                <div class="input input-sm flex items-center w-full text-base-content/40 text-xs font-mono">
                  {slugify(@title)}
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
              <.button
                type="button"
                phx-click="generate_seo"
                class="btn btn-sm btn-ghost w-full border border-base-content/20"
                disabled={@seo_generating}
              >
                <span :if={@seo_generating} class="loading loading-spinner loading-xs"></span>
                <.icon :if={!@seo_generating} name="hero-sparkles-mini" class="size-4" />
                {if @seo_generating, do: "Generating with AI...", else: "Generate with AI"}
              </.button>
            </.form>
          </div>

          <%!-- Actions --%>
          <div :if={length(@project.available_locales) > 1} class="p-5 border-b border-base-200">
            <h3 class="font-semibold text-sm mb-3 text-base-content/70 uppercase tracking-wide">
              Actions
            </h3>
            <div class="space-y-3">
              <form phx-change="update_copy_source">
                <span class="text-xs text-base-content/60 mb-1 block">Copy content from</span>
                <select
                  name="copy_source_locale"
                  class="select select-sm select-bordered w-full"
                >
                  <option
                    :for={loc <- @project.available_locales}
                    :if={loc != @current_locale}
                    value={loc}
                    selected={loc == @copy_source_locale}
                  >
                    {locale_display_name(loc)}
                  </option>
                </select>
              </form>
              <label class="flex items-center gap-2 cursor-pointer">
                <input
                  type="checkbox"
                  checked={@auto_translate}
                  phx-click="toggle_auto_translate"
                  class="checkbox checkbox-sm checkbox-primary"
                />
                <span class="text-sm text-base-content/70">Auto translate</span>
              </label>
              <.button
                type="button"
                phx-click="copy_content"
                class="btn btn-sm w-full border border-base-content/20"
                disabled={@copying_content || @copy_source_locale == nil}
              >
                <span :if={@copying_content} class="loading loading-spinner loading-xs"></span>
                <.icon :if={!@copying_content} name="hero-document-duplicate-mini" class="size-4" />
                {cond do
                  @copying_content -> "Copying..."
                  @auto_translate -> "Copy & Translate"
                  true -> "Copy content"
                end}
              </.button>
            </div>
          </div>

          <%!-- Page Settings --%>
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
              <% all_fields = Template.all_fields(@template) %>
              <div class="text-xs text-base-content/40">
                {length(all_fields)} {if length(all_fields) == 1,
                  do: "field",
                  else: "fields"}: {Enum.map_join(all_fields, ", ", & &1.label)}
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

      <%!-- Refine with AI dialog --%>
      <dialog
        :if={@refine_dialog}
        class="modal modal-open"
        phx-window-keydown="close_refine_dialog"
        phx-key="Escape"
      >
        <div class="modal-box max-w-md">
          <h3 class="font-bold text-lg flex items-center gap-2">
            <.icon name="hero-sparkles-mini" class="size-5" /> Refine "{@refine_dialog.label}"
          </h3>
          <form phx-submit="refine_content" class="mt-4 space-y-4">
            <input type="hidden" name="key" value={@refine_dialog.key} />
            <div>
              <label class="text-sm text-base-content/70 mb-1 block">
                What should the AI do?
              </label>
              <textarea
                name="instructions"
                class="textarea textarea-bordered w-full"
                rows="3"
                placeholder="e.g. Make it more concise, Summarize the body content here, Fix grammar..."
                autofocus
                required
              ></textarea>
              <p class="text-xs text-base-content/40 mt-1">
                The AI has access to all page fields for context.
              </p>
            </div>
            <div class="modal-action">
              <button type="button" phx-click="close_refine_dialog" class="btn btn-ghost btn-sm">
                Cancel
              </button>
              <button type="submit" class="btn btn-primary btn-sm gap-1">
                <.icon name="hero-sparkles-mini" class="size-4" /> Refine
              </button>
            </div>
          </form>
        </div>
        <div class="modal-backdrop" phx-click="close_refine_dialog"></div>
      </dialog>

      <%!-- Confirm copy overwrite dialog --%>
      <dialog
        :if={@show_copy_confirm}
        class="modal modal-open"
        phx-window-keydown="cancel_copy"
        phx-key="Escape"
      >
        <div class="modal-box max-w-sm">
          <h3 class="font-bold text-lg">Overwrite content?</h3>
          <p class="py-4 text-sm text-base-content/70">
            This will overwrite existing content in <strong>{String.upcase(@current_locale)}</strong>.
            Version history will preserve the current content.
          </p>
          <div class="modal-action">
            <button type="button" phx-click="cancel_copy" class="btn btn-ghost btn-sm">
              Cancel
            </button>
            <button type="button" phx-click="confirm_copy_content" class="btn btn-primary btn-sm">
              Continue
            </button>
          </div>
        </div>
        <div class="modal-backdrop" phx-click="cancel_copy"></div>
      </dialog>
    </Layouts.project>
    """
  end

  # Template item dispatcher — handles both Field and Group structs

  attr :item, :any, required: true
  attr :template_data, :map, required: true
  attr :refining_keys, :list, default: []

  defp template_item(%{item: %Field{}} = assigns) do
    value = Map.get(assigns.template_data, Atom.to_string(assigns.item.key))
    assigns = assign(assigns, field: assigns.item, value: value)

    ~H"""
    <.template_field field={@field} value={@value} refining_keys={@refining_keys} />
    """
  end

  defp template_item(%{item: %Group{}} = assigns) do
    ~H"""
    <fieldset>
      <legend class="text-xs font-semibold text-base-content/60 uppercase tracking-wide mb-3">
        {@item.label}
      </legend>
      <div
        class="grid gap-4"
        style={"grid-template-columns: repeat(#{length(@item.columns)}, minmax(0, 1fr))"}
      >
        <div :for={column <- @item.columns} class="space-y-4">
          <.template_field
            :for={field <- column.fields}
            field={field}
            value={Map.get(@template_data, Atom.to_string(field.key))}
            refining_keys={@refining_keys}
          />
        </div>
      </div>
    </fieldset>
    """
  end

  # Field rendering components

  attr :field, :any, required: true
  attr :value, :any, default: nil
  attr :refining_keys, :list, default: []

  defp template_field(%{field: %{type: :rich_text}} = assigns) do
    key = Atom.to_string(assigns.field.key)
    is_refining = Enum.member?(assigns.refining_keys, key)
    assigns = assign(assigns, :key, key) |> assign(:is_refining, is_refining)

    ~H"""
    <div>
      <div class="flex items-center justify-between mb-1">
        <label
          :if={@field.label != "Body"}
          class="text-xs font-medium text-base-content/60"
        >
          {@field.label}
          <span :if={@field.required} class="text-error">*</span>
        </label>
        <.refine_button :if={@field.ai_refine} key={@key} is_refining={@is_refining} />
      </div>
      <TiptapPhoenix.Component.tiptap_editor
        id={"tiptap-editor-#{@key}"}
        content={@value}
        section_key={@key}
      />
    </div>
    """
  end

  defp template_field(%{field: %{type: :text}} = assigns) do
    key = Atom.to_string(assigns.field.key)
    assigns = assign(assigns, :key, key)

    ~H"""
    <div>
      <label class="text-xs font-medium text-base-content/60 mb-1 block">
        {@field.label}
        <span :if={@field.required} class="text-error">*</span>
      </label>
      <input
        type="text"
        value={@value || ""}
        phx-debounce="300"
        name={"field[#{@key}]"}
        class="input input-bordered w-full"
        placeholder={@field.label}
      />
    </div>
    """
  end

  defp template_field(%{field: %{type: :textarea}} = assigns) do
    key = Atom.to_string(assigns.field.key)
    is_refining = Enum.member?(assigns.refining_keys, key)
    assigns = assign(assigns, :key, key) |> assign(:is_refining, is_refining)

    ~H"""
    <div>
      <div class="flex items-center justify-between mb-1">
        <label class="text-xs font-medium text-base-content/60">
          {@field.label}
          <span :if={@field.required} class="text-error">*</span>
        </label>
        <.refine_button :if={@field.ai_refine} key={@key} is_refining={@is_refining} />
      </div>
      <textarea
        phx-debounce="300"
        name={"field[#{@key}]"}
        class="textarea textarea-bordered w-full"
        rows="4"
        placeholder={@field.label}
      >{@value || ""}</textarea>
    </div>
    """
  end

  defp template_field(%{field: %{type: :image}} = assigns) do
    key = Atom.to_string(assigns.field.key)
    assigns = assign(assigns, :key, key)

    ~H"""
    <div>
      <label class="text-xs font-medium text-base-content/60 mb-1 block">
        {@field.label}
        <span :if={@field.required} class="text-error">*</span>
      </label>
      <input
        type="url"
        value={@value || ""}
        phx-debounce="300"
        name={"field[#{@key}]"}
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

  defp template_field(%{field: %{type: :url}} = assigns) do
    key = Atom.to_string(assigns.field.key)
    assigns = assign(assigns, :key, key)

    ~H"""
    <div>
      <label class="text-xs font-medium text-base-content/60 mb-1 block">
        {@field.label}
        <span :if={@field.required} class="text-error">*</span>
      </label>
      <input
        type="url"
        value={@value || ""}
        phx-debounce="300"
        name={"field[#{@key}]"}
        class="input input-bordered w-full"
        placeholder="https://..."
      />
    </div>
    """
  end

  defp template_field(%{field: %{type: :number}} = assigns) do
    key = Atom.to_string(assigns.field.key)
    assigns = assign(assigns, :key, key)

    ~H"""
    <div>
      <label class="text-xs font-medium text-base-content/60 mb-1 block">
        {@field.label}
        <span :if={@field.required} class="text-error">*</span>
      </label>
      <input
        type="number"
        value={@value}
        phx-debounce="300"
        name={"field[#{@key}]"}
        class="input input-bordered w-full"
      />
    </div>
    """
  end

  defp template_field(%{field: %{type: :select}} = assigns) do
    key = Atom.to_string(assigns.field.key)
    options = Map.get(assigns.field.constraints, :options, [])
    assigns = assign(assigns, key: key, options: options)

    ~H"""
    <div>
      <label class="text-xs font-medium text-base-content/60 mb-1 block">
        {@field.label}
        <span :if={@field.required} class="text-error">*</span>
      </label>
      <select
        name={"field[#{@key}]"}
        class="select select-bordered w-full"
      >
        <option value="">Select...</option>
        <option :for={opt <- @options} value={opt} selected={@value == opt}>{opt}</option>
      </select>
    </div>
    """
  end

  defp template_field(%{field: %{type: :toggle}} = assigns) do
    key = Atom.to_string(assigns.field.key)
    assigns = assign(assigns, :key, key)

    ~H"""
    <div class="flex items-center gap-3">
      <input type="hidden" name={"field[#{@key}]"} value="false" />
      <input
        type="checkbox"
        name={"field[#{@key}]"}
        value="true"
        checked={@value == true}
        class="toggle toggle-primary"
      />
      <label class="text-sm text-base-content/70">{@field.label}</label>
    </div>
    """
  end

  attr :key, :string, required: true
  attr :is_refining, :boolean, default: false

  defp refine_button(assigns) do
    ~H"""
    <button
      type="button"
      phx-click="open_refine_dialog"
      phx-value-key={@key}
      disabled={@is_refining}
      class="btn btn-ghost btn-xs gap-1"
    >
      <span :if={@is_refining} class="loading loading-spinner loading-xs"></span>
      <.icon :if={!@is_refining} name="hero-sparkles-mini" class="size-3.5" />
      {if @is_refining, do: "Refining...", else: "Refine with AI"}
    </button>
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
