# Page Publishing Simplification Design

## Problem

The current publishing system has two redundant layers:
1. Page-level status (draft/published/archived) — a global toggle
2. Per-locale published version via `PageLocale.published_version_id`

Additionally, the UI has three separate buttons (Save as Version, Publish, Publish Locale) that create confusion about what each does. Concurrent editing is not well-supported.

## Design

### Data Model Changes

**Page resource:**
- Remove `status` attribute (`:draft` / `:published` / `:archived`)
- Remove `published_at` timestamp
- Remove `:publish` and `:unpublish` actions
- Keep `archived_at` and `:archive`/`:restore` as separate page-level concern

**PageLocale resource — new attribute:**
- `has_unpublished_changes` (boolean, default `false`)
- Set to `true` on any auto-save
- Set to `false` on publish

**PageVersion — unchanged:**
- `is_current=true` marks the working draft (auto-saved in-place)
- Publishing creates a new immutable snapshot version

### Publishing Workflow

1. User edits content → auto-save updates draft in-place, sets `has_unpublished_changes=true` on PageLocale
2. User clicks **Publish (EN)** → creates new numbered PageVersion (snapshot of draft), sets `PageLocale.published_version_id` to it, sets `has_unpublished_changes=false`
3. User clicks **Unpublish (EN)** → sets `PageLocale.published_version_id` to `nil`
4. API returns `published_version` content (unchanged from today)

### UI Changes (Edit Sidebar)

**Remove:**
- "Save as Version" button
- Separate "Publish" (page-level) and "Publish Locale" buttons

**Replace with per-locale:**
- Status indicator: "Draft" / "Published (v3)" / "Unpublished changes"
- **Publish (EN)** button — creates snapshot + publishes
- **Unpublish (EN)** button — shown when locale has published version

### Concurrent Editing (Phoenix Presence)

- Track active editors via Phoenix Presence on topic `"page:{page_id}"`
- Show user avatars near locale tabs indicating who is editing which locale
- Last-write-wins for auto-save (no locking, no merging)
- Advisory locks remain for version creation race condition prevention

### Version History

- Each numbered version = a published snapshot (meaningful changelog)
- Working draft is not in history until published
- Rollback creates a new draft from historical version; user must Publish to make it live

### API

No changes to `GET /api/v1/projects/:slug/pages/published` — it already returns `PageLocale.published_version` content. The only change is that the page-level status check is removed from the query/policy.
