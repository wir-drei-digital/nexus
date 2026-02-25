# Page Publishing Simplification Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Simplify page publishing to per-locale only, remove page-level status, add presence awareness for concurrent editing.

**Architecture:** Remove `status`/`published_at` from Page resource. Add `has_unpublished_changes` to PageLocale. Merge publish actions into a single per-locale flow: Publish snapshots the draft into a new version and sets it as published. Add Phoenix Presence for editor awareness.

**Tech Stack:** Ash Framework, Phoenix LiveView, Phoenix Presence, PostgreSQL

---

### Task 1: Add `has_unpublished_changes` to PageLocale resource

**Files:**
- Modify: `lib/nexus/content/page_locale.ex`

**Step 1: Add attribute and update actions**

Add `has_unpublished_changes` boolean attribute (default `false`) to PageLocale. Update `publish_locale` action to also set `has_unpublished_changes` to `false`. Add a new `mark_changed` action that sets `has_unpublished_changes` to `true`.

```elixir
# In attributes block, add:
attribute :has_unpublished_changes, :boolean do
  default false
  allow_nil? false
  public? true
end

# Update publish_locale action:
update :publish_locale do
  accept [:published_version_id]
  change set_attribute(:has_unpublished_changes, false)
end

# Add mark_changed action:
update :mark_changed do
  accept []
  change set_attribute(:has_unpublished_changes, true)
end

# Add to code_interface:
define :mark_changed
```

**Step 2: Generate and run migration**

Run: `mix ash_postgres.generate_migrations --name add_has_unpublished_changes_to_page_locales`
Run: `mix ash.setup`

**Step 3: Commit**

```bash
git add lib/nexus/content/page_locale.ex priv/repo/migrations/ priv/resource_snapshots/
git commit -m "feat: add has_unpublished_changes to PageLocale"
```

---

### Task 2: Remove page-level publish status

**Files:**
- Modify: `lib/nexus/content/page.ex`

**Step 1: Remove status-related attributes and actions**

Remove from Page resource:
- `attribute :status` (lines 199-204)
- `attribute :published_at` (line 218)
- Actions `:publish` (lines 120-126) and `:unpublish` (lines 128-132)
- `define :publish` and `define :unpublish` from code_interface (lines 37-38)
- Remove `:publish, :unpublish` from the update policy action list (line 171) — keep the rest

In the read policy (line 163), change:
```elixir
authorize_if expr(project.is_public == true and status == :published)
```
to:
```elixir
authorize_if expr(project.is_public == true)
```

In the PageVersion read policy (file: `lib/nexus/content/page_version.ex`, line 113), change:
```elixir
authorize_if expr(page.project.is_public == true and page.status == :published)
```
to:
```elixir
authorize_if expr(page.project.is_public == true)
```

**Step 2: Generate and run migration**

Run: `mix ash_postgres.generate_migrations --name remove_page_status`
Run: `mix ash.setup`

**Step 3: Commit**

```bash
git add lib/nexus/content/page.ex lib/nexus/content/page_version.ex priv/repo/migrations/ priv/resource_snapshots/
git commit -m "feat: remove page-level publish status"
```

---

### Task 3: Update PageLive.Edit — new publish/unpublish handlers

**Files:**
- Modify: `lib/nexus_web/live/page_live/edit.ex`

**Step 1: Replace event handlers**

Remove the old `"publish"` handler (lines 218-230), `"unpublish"` handler (lines 233-245), and `"save_version"` handler (lines 184-215).

Replace `"publish_locale"` handler (lines 248-282) with a new `"publish"` handler that:
1. Calls `do_auto_save` first to ensure draft is saved
2. Creates a new PageVersion (snapshot of current draft)
3. Updates PageLocale's `published_version_id` to the new version
4. Sets `has_unpublished_changes` to `false`

```elixir
@impl true
def handle_event("publish", _params, socket) do
  user = socket.assigns.current_user
  page = socket.assigns.page
  locale = socket.assigns.current_locale
  keywords = parse_keywords(socket.assigns.meta_keywords)
  content_html = render_content_html(socket.assigns.template, socket.assigns.template_data)

  # Create a new published version (snapshot of current draft)
  version_attrs = %{
    page_id: page.id,
    locale: locale,
    title: socket.assigns.title,
    meta_description: socket.assigns.meta_description,
    meta_keywords: keywords,
    template_data: socket.assigns.template_data,
    content_html: content_html,
    created_by_id: user.id
  }

  page_locale = socket.assigns.locale_map[locale]

  with {:ok, published_version} <-
         Nexus.Content.PageVersion.create(version_attrs, actor: user),
       {:ok, _} <-
         Ash.update(page_locale, %{published_version_id: published_version.id},
           action: :publish_locale,
           actor: user
         ) do
    locales = load_locales(page, user)
    locale_map = Map.new(locales, &{&1.locale, &1})

    {:noreply,
     socket
     |> assign(:version, socket.assigns.version)
     |> assign(:locales, locales)
     |> assign(:locale_map, locale_map)
     |> assign(:save_status, :saved)
     |> put_flash(:info, "Published v#{published_version.version_number}")}
  else
    {:error, _} -> {:noreply, put_flash(socket, :error, "Failed to publish")}
  end
end
```

Add new `"unpublish"` handler:

```elixir
@impl true
def handle_event("unpublish", _params, socket) do
  user = socket.assigns.current_user
  page = socket.assigns.page
  locale = socket.assigns.current_locale
  page_locale = socket.assigns.locale_map[locale]

  case Ash.update(page_locale, %{}, action: :unpublish_locale, actor: user) do
    {:ok, _} ->
      locales = load_locales(page, user)
      locale_map = Map.new(locales, &{&1.locale, &1})

      {:noreply,
       socket
       |> assign(:locales, locales)
       |> assign(:locale_map, locale_map)
       |> put_flash(:info, "Locale unpublished")}

    {:error, _} ->
      {:noreply, put_flash(socket, :error, "Failed to unpublish")}
  end
end
```

**Step 2: Update `do_auto_save` to mark locale as changed**

After a successful auto-save, call `mark_changed` on the PageLocale if `has_unpublished_changes` is currently `false`:

```elixir
defp do_auto_save(socket) do
  # ... existing logic ...
  # After successful save, mark locale as having unpublished changes
  socket = maybe_mark_locale_changed(socket)
  socket
end

defp maybe_mark_locale_changed(socket) do
  locale = socket.assigns.current_locale
  page_locale = socket.assigns.locale_map[locale]

  if page_locale && page_locale.published_version_id && !page_locale.has_unpublished_changes do
    case Ash.update(page_locale, %{}, action: :mark_changed, actor: socket.assigns.current_user) do
      {:ok, updated_locale} ->
        locale_map = Map.put(socket.assigns.locale_map, locale, updated_locale)
        locales = Enum.map(socket.assigns.locales, fn l ->
          if l.id == updated_locale.id, do: updated_locale, else: l
        end)
        assign(socket, locale_map: locale_map, locales: locales)
      {:error, _} ->
        socket
    end
  else
    socket
  end
end
```

**Step 3: Commit**

```bash
git add lib/nexus_web/live/page_live/edit.ex
git commit -m "feat: replace publish handlers with per-locale workflow"
```

---

### Task 4: Update sidebar UI

**Files:**
- Modify: `lib/nexus_web/live/page_live/edit.ex` (render function, lines 1059-1110)

**Step 1: Replace the publish section in the sidebar**

Replace the current publish section (lines 1059-1111) with:

```heex
<%!-- Publish --%>
<div class="p-5 border-b border-base-200">
  <h3 class="font-semibold text-sm mb-3 text-base-content/70 uppercase tracking-wide">
    Publish
  </h3>
  <div class="space-y-3">
    <% page_locale = @locale_map[@current_locale] %>
    <% is_published = page_locale && page_locale.published_version_id != nil %>
    <% has_changes = page_locale && page_locale.has_unpublished_changes %>
    <div class="flex items-center justify-between">
      <span class="text-sm text-base-content/60">Status</span>
      <span class={[
        "badge badge-sm",
        is_published && !has_changes && "badge-success",
        is_published && has_changes && "badge-warning",
        !is_published && "badge-neutral"
      ]}>
        <%= cond do %>
          <% is_published && has_changes -> %>Unpublished changes
          <% is_published -> %>
            Published (v{page_locale.published_version.version_number})
          <% true -> %>Draft
        <% end %>
      </span>
    </div>
    <%!-- Save status indicator --%>
    <div class="flex items-center gap-1.5 text-sm">
      <.save_status_indicator status={@save_status} />
    </div>

    <div class="flex gap-2">
      <.button
        phx-click="publish"
        class="btn btn-success btn-sm flex-1"
        phx-disable-with="Publishing..."
      >
        Publish ({String.upcase(@current_locale)})
      </.button>
      <.button
        :if={is_published}
        phx-click="unpublish"
        class="btn btn-warning btn-sm flex-1"
      >
        Unpublish
      </.button>
    </div>
  </div>
</div>
```

**Step 2: Commit**

```bash
git add lib/nexus_web/live/page_live/edit.ex
git commit -m "feat: update sidebar UI for per-locale publishing"
```

---

### Task 5: Update sidebar page tree status indicators

**Files:**
- Modify: `lib/nexus_web/components/layouts.ex` (lines 293, 326)

**Step 1: Update page tree items**

The sidebar tree currently shows a green dot when `@item.data.status == :published`. Since we're removing page-level status, we need to either:
- Remove the indicator entirely, or
- Load locale publishing state (heavier)

For simplicity, remove the page-level status dot from the tree. The locale tabs already show per-locale publishing state.

Replace `@item.data.status == :published` with `false` (or remove the `:if` span entirely) at both locations (lines 293 and 326).

**Step 2: Commit**

```bash
git add lib/nexus_web/components/layouts.ex
git commit -m "feat: remove page-level status indicator from sidebar tree"
```

---

### Task 6: Add Phoenix Presence for editor awareness

**Files:**
- Create: `lib/nexus_web/presence.ex`
- Modify: `lib/nexus_web/live/page_live/edit.ex`

**Step 1: Create Presence module**

```elixir
defmodule NexusWeb.Presence do
  use Phoenix.Presence,
    otp_app: :nexus,
    pubsub_server: Nexus.PubSub
end
```

**Step 2: Add Presence to supervision tree**

Modify `lib/nexus/application.ex` — add `NexusWeb.Presence` to the children list.

**Step 3: Track presence in PageLive.Edit mount**

In mount, after successful page load:
```elixir
topic = "page:#{page.id}"
if connected?(socket) do
  NexusWeb.Presence.track(self(), topic, user.id, %{
    name: user.email,
    locale: locale
  })
  NexusWeb.Endpoint.subscribe(topic)
end
```

Add assigns:
```elixir
|> assign(:presences, %{})
```

**Step 4: Update presence on locale switch**

In `handle_event("switch_locale", ...)`, update the presence metadata:
```elixir
if connected?(socket) do
  NexusWeb.Presence.update(self(), "page:#{page.id}", user.id, %{
    name: user.email,
    locale: locale
  })
end
```

**Step 5: Handle presence diffs**

```elixir
@impl true
def handle_info(%Phoenix.Socket.Broadcast{event: "presence_diff"}, socket) do
  presences =
    NexusWeb.Presence.list("page:#{socket.assigns.page.id}")
    |> Enum.reject(fn {uid, _} -> uid == to_string(socket.assigns.current_user.id) end)
    |> Enum.map(fn {_uid, %{metas: [meta | _]}} -> meta end)

  {:noreply, assign(socket, :presences, presences)}
end
```

**Step 6: Show presence avatars near locale tabs**

Add a small indicator near locale tabs showing other editors:

```heex
<%!-- Active editors --%>
<div :if={@presences != []} class="flex items-center gap-1 ml-2">
  <div
    :for={p <- @presences}
    class="tooltip tooltip-bottom"
    data-tip={"#{p.name} editing #{String.upcase(p.locale)}"}
  >
    <div class="avatar placeholder">
      <div class="bg-neutral text-neutral-content w-6 rounded-full text-xs">
        {String.first(p.name)}
      </div>
    </div>
  </div>
</div>
```

**Step 7: Commit**

```bash
git add lib/nexus_web/presence.ex lib/nexus/application.ex lib/nexus_web/live/page_live/edit.ex
git commit -m "feat: add Phoenix Presence for editor awareness"
```

---

### Task 7: Update version history page

**Files:**
- Modify: `lib/nexus_web/live/page_live/versions.ex`

**Step 1: Mark published versions in history**

Load the PageLocale for the current locale to know which version is published. Add a "Published" badge next to the version that matches `page_locale.published_version_id`.

In mount, add:
```elixir
locales = Nexus.Content.PageLocale.for_page!(page.id, actor: user, load: [:published_version])
locale_map = Map.new(locales, &{&1.locale, &1})
```
Assign `:locale_map`.

In render, add a badge:
```heex
<span :if={version.id == (@locale_map[@current_locale] && @locale_map[@current_locale].published_version_id)}
  class="badge badge-success badge-sm">Published</span>
```

**Step 2: Commit**

```bash
git add lib/nexus_web/live/page_live/versions.ex
git commit -m "feat: show published badge in version history"
```

---

### Task 8: Verify and test

**Step 1: Run existing tests**

Run: `mix test`
Fix any failures caused by removal of page status.

**Step 2: Manual verification**

- Edit a page, verify auto-save works and status shows "Draft"
- Publish a locale, verify status changes to "Published (vN)"
- Edit after publishing, verify status changes to "Unpublished changes"
- Unpublish, verify status changes to "Draft"
- Open page in two browser windows, verify presence shows the other editor
- Call API endpoint, verify it returns published version content
- Check version history shows "Published" badge on correct version

**Step 3: Run precommit**

Run: `mix precommit`
Fix any compilation warnings or formatting issues.

**Step 4: Final commit**

```bash
git commit -m "chore: fix tests and warnings"
```
