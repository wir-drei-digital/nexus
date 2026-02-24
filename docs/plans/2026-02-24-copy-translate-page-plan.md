# Copy/Translate Page Content — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a sidebar action that copies page content from one locale into another, optionally translating text fields via LLM.

**Architecture:** New `translate_content` action on `Nexus.AI.Assistant` with a single LLM call for all translatable fields. A `to_markdown` function is added to `ProseMirror` to convert rich_text for LLM input. The page editor sidebar gets an "Actions" section with source locale dropdown, auto-translate checkbox, and copy button. A confirmation dialog prevents accidental overwrites.

**Tech Stack:** Elixir, Ash Framework, Phoenix LiveView, ReqLLM (OpenRouter API), ProseMirror/TipTap

---

### Task 1: Add `to_markdown` to ProseMirror module

We need ProseMirror JSON → Markdown conversion for feeding rich_text fields to the LLM. The existing module only has `from_markdown` (Markdown → ProseMirror) and `to_plain_text`.

**Files:**
- Modify: `lib/nexus/ai/prosemirror.ex`
- Create: `test/nexus/ai/prosemirror_test.exs`

**Step 1: Write the failing test**

```elixir
# test/nexus/ai/prosemirror_test.exs
defmodule Nexus.AI.ProseMirrorTest do
  use ExUnit.Case, async: true

  alias Nexus.AI.ProseMirror

  describe "to_markdown/1" do
    test "converts paragraph to markdown" do
      doc = %{
        "type" => "doc",
        "content" => [
          %{"type" => "paragraph", "content" => [%{"type" => "text", "text" => "Hello world"}]}
        ]
      }

      assert ProseMirror.to_markdown(doc) == "Hello world"
    end

    test "converts heading to markdown" do
      doc = %{
        "type" => "doc",
        "content" => [
          %{
            "type" => "heading",
            "attrs" => %{"level" => 2},
            "content" => [%{"type" => "text", "text" => "Title"}]
          }
        ]
      }

      assert ProseMirror.to_markdown(doc) == "## Title"
    end

    test "converts bold and italic marks" do
      doc = %{
        "type" => "doc",
        "content" => [
          %{
            "type" => "paragraph",
            "content" => [
              %{"type" => "text", "text" => "bold", "marks" => [%{"type" => "bold"}]},
              %{"type" => "text", "text" => " and "},
              %{"type" => "text", "text" => "italic", "marks" => [%{"type" => "italic"}]}
            ]
          }
        ]
      }

      assert ProseMirror.to_markdown(doc) == "**bold** and *italic*"
    end

    test "converts bullet list" do
      doc = %{
        "type" => "doc",
        "content" => [
          %{
            "type" => "bulletList",
            "content" => [
              %{
                "type" => "listItem",
                "content" => [
                  %{
                    "type" => "paragraph",
                    "content" => [%{"type" => "text", "text" => "Item 1"}]
                  }
                ]
              },
              %{
                "type" => "listItem",
                "content" => [
                  %{
                    "type" => "paragraph",
                    "content" => [%{"type" => "text", "text" => "Item 2"}]
                  }
                ]
              }
            ]
          }
        ]
      }

      assert ProseMirror.to_markdown(doc) == "- Item 1\n- Item 2"
    end

    test "converts link marks" do
      doc = %{
        "type" => "doc",
        "content" => [
          %{
            "type" => "paragraph",
            "content" => [
              %{
                "type" => "text",
                "text" => "click here",
                "marks" => [
                  %{"type" => "link", "attrs" => %{"href" => "https://example.com"}}
                ]
              }
            ]
          }
        ]
      }

      assert ProseMirror.to_markdown(doc) == "[click here](https://example.com)"
    end

    test "returns empty string for empty doc" do
      assert ProseMirror.to_markdown(%{"type" => "doc", "content" => [%{"type" => "paragraph"}]}) ==
               ""
    end

    test "returns empty string for nil" do
      assert ProseMirror.to_markdown(nil) == ""
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `mix test test/nexus/ai/prosemirror_test.exs`
Expected: FAIL — `to_markdown` function undefined

**Step 3: Write the implementation**

Add to `lib/nexus/ai/prosemirror.ex` after the `to_plain_text` functions:

```elixir
@doc """
Converts a ProseMirror JSON document to Markdown string.
Used for feeding rich text content to LLMs for translation.
"""
@spec to_markdown(map() | nil) :: String.t()
def to_markdown(nil), do: ""
def to_markdown(%{"type" => "doc", "content" => content}) when is_list(content) do
  content
  |> Enum.map(&node_to_markdown/1)
  |> Enum.reject(&(&1 == ""))
  |> Enum.join("\n\n")
end
def to_markdown(%{"type" => "doc"}), do: ""
def to_markdown(_), do: ""

# -- ProseMirror JSON → Markdown (private) --

defp node_to_markdown(%{"type" => "paragraph", "content" => content}) do
  inline_to_markdown(content)
end
defp node_to_markdown(%{"type" => "paragraph"}), do: ""

defp node_to_markdown(%{"type" => "heading", "attrs" => %{"level" => level}, "content" => content}) do
  prefix = String.duplicate("#", level)
  "#{prefix} #{inline_to_markdown(content)}"
end
defp node_to_markdown(%{"type" => "heading"}), do: ""

defp node_to_markdown(%{"type" => "codeBlock", "content" => [%{"text" => text}]} = node) do
  lang = get_in(node, ["attrs", "language"]) || ""
  "```#{lang}\n#{text}\n```"
end
defp node_to_markdown(%{"type" => "codeBlock"}), do: "```\n```"

defp node_to_markdown(%{"type" => "blockquote", "content" => content}) do
  content
  |> Enum.map(&node_to_markdown/1)
  |> Enum.reject(&(&1 == ""))
  |> Enum.map_join("\n", &("> " <> &1))
end

defp node_to_markdown(%{"type" => "bulletList", "content" => items}) do
  items
  |> Enum.map(fn %{"content" => content} ->
    text = content |> Enum.map(&node_to_markdown/1) |> Enum.join("\n")
    "- #{text}"
  end)
  |> Enum.join("\n")
end

defp node_to_markdown(%{"type" => "orderedList", "content" => items}) do
  items
  |> Enum.with_index(1)
  |> Enum.map(fn {%{"content" => content}, idx} ->
    text = content |> Enum.map(&node_to_markdown/1) |> Enum.join("\n")
    "#{idx}. #{text}"
  end)
  |> Enum.join("\n")
end

defp node_to_markdown(%{"type" => "horizontalRule"}), do: "---"

defp node_to_markdown(%{"type" => "image", "attrs" => attrs}) do
  alt = attrs["alt"] || ""
  src = attrs["src"] || ""
  "![#{alt}](#{src})"
end

defp node_to_markdown(_), do: ""

defp inline_to_markdown(nodes) when is_list(nodes) do
  Enum.map_join(nodes, "", &inline_node_to_markdown/1)
end

defp inline_node_to_markdown(%{"type" => "text", "text" => text} = node) do
  marks = Map.get(node, "marks", [])
  wrap_with_marks(text, marks)
end
defp inline_node_to_markdown(%{"type" => "hardBreak"}), do: "\n"
defp inline_node_to_markdown(_), do: ""

defp wrap_with_marks(text, []), do: text
defp wrap_with_marks(text, [%{"type" => "bold"} | rest]),
  do: wrap_with_marks("**#{text}**", rest)
defp wrap_with_marks(text, [%{"type" => "italic"} | rest]),
  do: wrap_with_marks("*#{text}*", rest)
defp wrap_with_marks(text, [%{"type" => "strike"} | rest]),
  do: wrap_with_marks("~~#{text}~~", rest)
defp wrap_with_marks(text, [%{"type" => "code"} | rest]),
  do: wrap_with_marks("`#{text}`", rest)
defp wrap_with_marks(text, [%{"type" => "link", "attrs" => %{"href" => href}} | rest]),
  do: wrap_with_marks("[#{text}](#{href})", rest)
defp wrap_with_marks(text, [_ | rest]), do: wrap_with_marks(text, rest)
```

**Step 4: Run tests to verify they pass**

Run: `mix test test/nexus/ai/prosemirror_test.exs`
Expected: All PASS

**Step 5: Commit**

```bash
git add lib/nexus/ai/prosemirror.ex test/nexus/ai/prosemirror_test.exs
git commit -m "feat: add to_markdown conversion to ProseMirror module"
```

---

### Task 2: Add `translate_content` action to AI.Assistant

Add the LLM-powered translation action that takes a map of fields and translates them from one locale to another.

**Files:**
- Modify: `lib/nexus/ai/assistant.ex`
- Modify: `lib/nexus/ai/helpers.ex`

**Step 1: Write the failing test**

```elixir
# test/nexus/ai/translate_content_test.exs
defmodule Nexus.AI.TranslateContentTest do
  use ExUnit.Case, async: true

  import Mox

  alias Nexus.AI.Helpers

  # Since we can't call the real LLM in tests, we test the field
  # preparation and response parsing logic by testing the internal
  # helper that prepares content and parses results.

  describe "classify_fields/2" do
    test "separates translatable from direct-copy fields" do
      template_data = %{
        "body" => %{"type" => "doc", "content" => [%{"type" => "paragraph", "content" => [%{"type" => "text", "text" => "Hello"}]}]},
        "hero_image" => "https://example.com/img.jpg",
        "cta_url" => "https://example.com",
        "featured" => true
      }

      field_types = %{
        "body" => :rich_text,
        "hero_image" => :image,
        "cta_url" => :url,
        "featured" => :toggle
      }

      {translatable, direct} = Helpers.classify_fields(template_data, field_types)

      assert Map.has_key?(translatable, "body")
      assert Map.has_key?(direct, "hero_image")
      assert Map.has_key?(direct, "cta_url")
      assert Map.has_key?(direct, "featured")
      refute Map.has_key?(translatable, "hero_image")
    end
  end

  describe "prepare_translation_content/2" do
    test "converts rich_text fields to markdown" do
      translatable = %{
        "body" => %{"type" => "doc", "content" => [%{"type" => "paragraph", "content" => [%{"type" => "text", "text" => "Hello world"}]}]},
        "headline" => "Welcome"
      }

      field_types = %{"body" => :rich_text, "headline" => :text}

      prepared = Helpers.prepare_translation_content(translatable, field_types)

      assert prepared["body"] == "Hello world"
      assert prepared["headline"] == "Welcome"
    end
  end

  describe "apply_translation_results/3" do
    test "converts markdown results back to ProseMirror for rich_text fields" do
      results = %{
        "body" => "Hallo Welt",
        "headline" => "Willkommen"
      }

      field_types = %{"body" => :rich_text, "headline" => :text}

      applied = Helpers.apply_translation_results(results, field_types)

      assert %{"type" => "doc", "content" => _} = applied["body"]
      assert applied["headline"] == "Willkommen"
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `mix test test/nexus/ai/translate_content_test.exs`
Expected: FAIL — functions undefined

**Step 3: Write the implementation**

Add to `lib/nexus/ai/helpers.ex`:

```elixir
@translatable_types [:text, :textarea, :rich_text]

@doc """
Classifies template_data fields into translatable and direct-copy buckets
based on their field types.
"""
def classify_fields(template_data, field_types) do
  Enum.reduce(template_data, {%{}, %{}}, fn {key, value}, {translatable, direct} ->
    type = Map.get(field_types, key)

    if type in @translatable_types do
      {Map.put(translatable, key, value), direct}
    else
      {translatable, Map.put(direct, key, value)}
    end
  end)
end

@doc """
Prepares translatable fields for LLM input.
Converts rich_text ProseMirror JSON to markdown, leaves others as strings.
"""
def prepare_translation_content(translatable, field_types) do
  Map.new(translatable, fn {key, value} ->
    case Map.get(field_types, key) do
      :rich_text -> {key, ProseMirror.to_markdown(value)}
      _ -> {key, to_string(value || "")}
    end
  end)
end

@doc """
Applies translation results, converting markdown back to ProseMirror for rich_text fields.
"""
def apply_translation_results(results, field_types) do
  Map.new(results, fn {key, value} ->
    case Map.get(field_types, key) do
      :rich_text ->
        case ProseMirror.from_markdown(to_string(value)) do
          {:ok, doc} -> {key, doc}
          {:error, _} -> {key, ProseMirror.default_doc()}
        end

      _ ->
        {key, to_string(value)}
    end
  end)
end

@doc """
Translates a map of content from source_locale to target_locale using LLM.
"""
def translate_content_impl(content, source_locale, target_locale, field_types) do
  prepared = prepare_translation_content(content, field_types)

  prompt_messages =
    ReqLLM.Context.new([
      ReqLLM.Context.system("""
      You are a professional translator. Translate all content from #{locale_name(source_locale)} to #{locale_name(target_locale)}.
      Preserve all formatting, markdown structure, links, and special characters exactly.
      Do not add or remove any content — translate faithfully.
      """),
      ReqLLM.Context.user("""
      Translate each field value below. Return a JSON object with the same keys but translated values.

      #{Jason.encode!(prepared, pretty: true)}
      """)
    ])

  schema =
    Enum.map(prepared, fn {key, _} ->
      {String.to_atom(key), [type: :string, required: true]}
    end)

  case ReqLLM.generate_object(@model, prompt_messages, schema) do
    {:ok, response} ->
      translated = ReqLLM.Response.object(response)
      # Ensure all keys are strings
      translated = Map.new(translated, fn {k, v} -> {to_string(k), v} end)
      {:ok, apply_translation_results(translated, field_types)}

    {:error, reason} ->
      {:error, "Translation failed: #{inspect(reason)}"}
  end
end

defp locale_name(code) do
  %{
    "en" => "English", "de" => "German", "fr" => "French", "es" => "Spanish",
    "it" => "Italian", "pt" => "Portuguese", "nl" => "Dutch", "pl" => "Polish",
    "ru" => "Russian", "zh" => "Chinese", "ja" => "Japanese", "ko" => "Korean",
    "ar" => "Arabic"
  }
  |> Map.get(code, code)
end
```

Add to `lib/nexus/ai/assistant.ex` — new action + code_interface + policy:

```elixir
# In code_interface:
define :translate_content, args: [:content, :source_locale, :target_locale, :field_types]

# In actions:
action :translate_content do
  argument :content, :map, allow_nil?: false
  argument :source_locale, :string, allow_nil?: false
  argument :target_locale, :string, allow_nil?: false
  argument :field_types, :map, allow_nil?: false
  returns :map

  run fn input, _context ->
    args = input.arguments
    Nexus.AI.Helpers.translate_content_impl(
      args.content,
      args.source_locale,
      args.target_locale,
      args.field_types
    )
  end
end

# In policies:
policy action(:translate_content) do
  authorize_if always()
end
```

**Step 4: Run tests to verify they pass**

Run: `mix test test/nexus/ai/translate_content_test.exs`
Expected: All PASS

**Step 5: Commit**

```bash
git add lib/nexus/ai/assistant.ex lib/nexus/ai/helpers.ex test/nexus/ai/translate_content_test.exs
git commit -m "feat: add translate_content action for multi-field LLM translation"
```

---

### Task 3: Add copy/translate UI to the sidebar

Add the "Actions" section to the page editor sidebar with source locale dropdown, auto-translate checkbox, copy button, and confirmation dialog.

**Files:**
- Modify: `lib/nexus_web/live/page_live/edit.ex`

**Step 1: Add new assigns in mount**

In the `mount` function, after the existing assigns (line ~43 area), add:

```elixir
|> assign(:copy_source_locale, default_copy_source(project, locale))
|> assign(:auto_translate, true)
|> assign(:copying_content, false)
|> assign(:show_copy_confirm, false)
```

Add helper at end of module:

```elixir
defp default_copy_source(project, current_locale) do
  if project.default_locale != current_locale do
    project.default_locale
  else
    project.available_locales
    |> Enum.find(& &1 != current_locale)
  end
end
```

**Step 2: Add sidebar "Actions" section**

In the `render/1` function, insert a new section between the "SEO Settings" section and "Page Settings" section (after the `</.form>` closing the SEO section, around line 815):

```heex
<%!-- Actions --%>
<div class="p-5 border-b border-base-200">
  <h3 class="font-semibold text-sm mb-3 text-base-content/70 uppercase tracking-wide">
    Actions
  </h3>
  <div class="space-y-3">
    <div>
      <span class="text-xs text-base-content/60 mb-1 block">Copy content from</span>
      <select
        name="copy_source_locale"
        phx-change="update_copy_source"
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
    </div>
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
```

Add confirmation dialog at the end of render (before `</Layouts.project>`), alongside the existing refine dialog:

```heex
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
      This will overwrite existing content in
      <strong>{String.upcase(@current_locale)}</strong>.
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
```

Add the helper function:

```elixir
defp locale_display_name(code) do
  %{
    "en" => "English", "de" => "German", "fr" => "French", "es" => "Spanish",
    "it" => "Italian", "pt" => "Portuguese", "nl" => "Dutch", "pl" => "Polish",
    "ru" => "Russian", "zh" => "Chinese", "ja" => "Japanese", "ko" => "Korean",
    "ar" => "Arabic"
  }
  |> Map.get(code, String.upcase(code))
end
```

**Step 3: Commit UI skeleton**

```bash
git add lib/nexus_web/live/page_live/edit.ex
git commit -m "feat: add copy/translate actions section to page editor sidebar"
```

---

### Task 4: Add event handlers for copy/translate flow

Wire up the LiveView event handlers and async flow for copy + translate.

**Files:**
- Modify: `lib/nexus_web/live/page_live/edit.ex`

**Step 1: Add event handlers**

Add the following event handlers to `edit.ex`:

```elixir
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
  # Check if target locale has existing content
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
```

**Step 2: Add copy logic**

```elixir
defp do_copy_content(socket) do
  source_locale = socket.assigns.copy_source_locale
  page = socket.assigns.page
  template = socket.assigns.template

  source_version = load_current_version(page, source_locale)

  if source_version == nil do
    put_flash(socket, :error, "No content found for #{String.upcase(source_locale)}")
  else
    source_template_data = extract_template_data(source_version, template)

    # Build field_types map from template
    field_types =
      Template.all_fields(template)
      |> Map.new(fn field -> {Atom.to_string(field.key), field.type} end)

    # SEO fields to copy
    seo_data = %{
      title: source_version.title || "",
      meta_description: source_version.meta_description || "",
      og_title: source_version.og_title || "",
      og_description: source_version.og_description || "",
      meta_keywords: source_version.meta_keywords || [],
      og_image_url: source_version.og_image_url || ""
    }

    if socket.assigns.auto_translate do
      do_copy_with_translation(socket, source_template_data, seo_data, field_types, source_locale)
    else
      do_copy_without_translation(socket, source_template_data, seo_data, template)
    end
  end
end

defp do_copy_with_translation(socket, source_template_data, seo_data, field_types, source_locale) do
  target_locale = socket.assigns.current_locale

  # Classify template fields
  {translatable_template, direct_template} =
    Nexus.AI.Helpers.classify_fields(source_template_data, field_types)

  # Classify SEO fields: translatable vs direct-copy
  seo_translatable = %{
    "title" => seo_data.title,
    "meta_description" => seo_data.meta_description,
    "og_title" => seo_data.og_title,
    "og_description" => seo_data.og_description
  }

  seo_field_types = %{
    "title" => :text,
    "meta_description" => :textarea,
    "og_title" => :text,
    "og_description" => :textarea
  }

  # Merge all translatable content
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

  # Push content to TipTap editors
  socket =
    Enum.reduce(Template.all_fields(template), socket, fn field, sock ->
      if field.type == :rich_text do
        key = Atom.to_string(field.key)
        content = Map.get(source_template_data, key, Template.default_data(template)[key])
        push_event(sock, "tiptap:set_content:#{key}", %{content: content})
      else
        sock
      end
    end)

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
```

**Step 3: Add async result handlers**

```elixir
@impl true
def handle_async(:copy_translate, {:ok, {:ok, translated, direct_template, seo_data}}, socket) do
  socket = cancel_auto_save_timer(socket)
  template = socket.assigns.template

  # Merge translated template fields with direct-copy fields
  translated_template =
    Map.take(translated, Enum.map(Template.all_fields(template), &Atom.to_string(&1.key)))

  new_template_data = Map.merge(direct_template, translated_template)

  # Extract translated SEO fields
  new_title = translated["title"] || seo_data.title
  new_meta_desc = translated["meta_description"] || seo_data.meta_description

  # Push rich text content to TipTap editors
  socket =
    Enum.reduce(Template.all_fields(template), socket, fn field, sock ->
      if field.type == :rich_text do
        key = Atom.to_string(field.key)
        content = Map.get(new_template_data, key, Template.default_data(template)[key])
        push_event(sock, "tiptap:set_content:#{key}", %{content: content})
      else
        sock
      end
    end)

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
   |> put_flash(:info, "Content translated from #{String.upcase(socket.assigns.copy_source_locale)}")}
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
```

**Step 4: Update `switch_locale` to reset copy_source**

In the existing `handle_event("switch_locale", ...)`, add at the end before the `{:noreply, ...}`:

```elixir
|> assign(:copy_source_locale, default_copy_source(socket.assigns.project, locale))
|> assign(:show_copy_confirm, false)
```

**Step 5: Run full test suite**

Run: `mix test`
Expected: All PASS

**Step 6: Commit**

```bash
git add lib/nexus_web/live/page_live/edit.ex
git commit -m "feat: add copy/translate event handlers and async flow"
```

---

### Task 5: Manual verification and final commit

**Step 1: Start dev server and verify**

Run: `mix phx.server`

1. Navigate to a page with multiple locale tabs
2. Switch to a non-default locale (e.g., "de")
3. Verify the "Actions" section appears in the sidebar
4. Verify the source dropdown defaults to the project default locale
5. Verify the auto-translate checkbox is checked by default
6. Test copy without translation: uncheck auto-translate, click "Copy content"
7. Test copy with translation: check auto-translate, click "Copy & Translate"
8. Test overwrite confirmation: add content to target locale first, then copy again

**Step 2: Run precommit**

Run: `mix precommit`
Expected: All checks pass

**Step 3: Final commit if any formatting changes**

```bash
git add -A
git commit -m "chore: format copy/translate feature code"
```
