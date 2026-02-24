# Media System Design

## Overview

Add a complete image media system to Nexus CMS: upload images, manage them in a project media library, insert them into tiptap rich text editors, and use them in template image fields. Support local filesystem and S3 storage backends. Generate image variants (thumbnail, medium, large) on upload.

## Requirements

- Images only (JPEG, PNG, GIF, WebP, SVG)
- Per-project media library
- Upload via drag-drop, file picker, tiptap editor, or slash command
- Multiple variants: thumb (300px), medium (800px), large (1600px), original
- Local and S3 storage backends
- Proxy controller serving all images via `/media/*` regardless of backend
- Media library page accessible from sidebar nav
- Media picker modal for tiptap and template image fields

## Data Model

### New Domain: `Nexus.Media`

### Resource: `Nexus.Media.MediaItem`

| Attribute       | Type        | Notes                                              |
|-----------------|-------------|----------------------------------------------------|
| id              | uuid_v7     | Primary key                                        |
| filename        | string      | Original upload filename                           |
| file_path       | string      | Relative storage path: `{project_id}/{id}{ext}`    |
| mime_type       | string      | e.g. `image/jpeg`                                  |
| file_size       | integer     | Bytes                                              |
| width           | integer     | Original pixel width (set after processing)        |
| height          | integer     | Original pixel height (set after processing)       |
| alt_text        | string      | Optional, for accessibility                        |
| variants        | map         | `%{"thumb" => "path", "medium" => "path", ...}`    |
| storage_backend | string      | `"local"` or `"s3"` (records which backend stored) |
| status          | atom        | `:pending`, `:processing`, `:ready`, `:error`      |
| project_id      | uuid        | belongs_to Project                                 |
| uploaded_by_id  | uuid        | belongs_to User                                    |
| inserted_at     | utc_datetime|                                                    |
| updated_at      | utc_datetime|                                                    |

### Actions

- `create` — create from upload (sets status: :pending, triggers processing)
- `list_for_project` — paginated list for project gallery
- `update` — alt_text only
- `destroy` — deletes record + all stored files (original + variants)
- `update_status` — internal, used by processor to set status/variants/dimensions

### Variant Sizes

| Name     | Max Width | Use Case               |
|----------|-----------|------------------------|
| thumb    | 300px     | Gallery grid, sidebar  |
| medium   | 800px     | Inline content         |
| large    | 1600px    | Hero images, full-width|
| original | unchanged | Download, source       |

SVGs skip variant generation (served as-is).

Only downscale — if original is smaller than a variant size, that variant is skipped.

## Storage Backend

### `Nexus.Media.Storage`

Abstraction layer with identical API for both backends:

- `store(relative_path, content, opts)` — store binary content
- `get(relative_path, opts)` — retrieve binary content
- `delete(relative_path, opts)` — remove file
- `url(relative_path)` — returns public proxy URL (`/media/{relative_path}`)

### `Nexus.Media.Storage.Local`

- Base directory: `priv/static/uploads/media/`
- Path traversal protection
- Dev/test default

### `Nexus.Media.Storage.S3`

- Uses `ex_aws_s3` for S3-compatible storage (AWS, Tigris, MinIO)
- Key prefix: `media/`
- Content-type set from MIME type

### Path Format

```
{project_id}/{media_item_id}.jpg          # original
{project_id}/{media_item_id}_thumb.jpg    # thumbnail
{project_id}/{media_item_id}_medium.jpg   # medium
{project_id}/{media_item_id}_large.jpg    # large
```

### Configuration

```elixir
# dev.exs / test.exs
config :nexus, :storage_backend, :local

# runtime.exs (production)
config :nexus, :storage_backend, :s3
config :nexus, :s3,
  access_key_id: System.get_env("AWS_ACCESS_KEY_ID"),
  secret_access_key: System.get_env("AWS_SECRET_ACCESS_KEY"),
  region: System.get_env("AWS_REGION", "auto"),
  bucket: System.get_env("AWS_BUCKET"),
  host: System.get_env("AWS_S3_HOST"),
  scheme: "https://",
  prefix: "media"
```

## Proxy Controller

### `NexusWeb.MediaController`

All images served via a single public endpoint:

```
GET /media/:path  (e.g. /media/abc123/def456_medium.jpg)
```

Behavior:
- Reads file from the configured storage backend using the path
- Sets `Content-Type` from the file's MIME type
- Sets `Cache-Control: public, max-age=31536000, immutable` (paths contain the ID, so they're immutable)
- Sets `ETag` based on file path
- Returns 404 for missing files
- No authentication required (public CMS images)

Route placement: outside the auth-protected scope, in a lightweight pipeline.

## Image Processing

### `Nexus.Media.Processor`

Uses the `image` hex package (libvips via Vix) for fast, low-memory image processing.

Runs as an **Oban job** in `:media_processing` queue when a MediaItem is created with status `:pending`:

1. Update status to `:processing`
2. Read original from storage
3. Extract width/height from image metadata
4. For each variant size (thumb, medium, large):
   - Skip if original width <= variant width
   - Resize to variant width (maintain aspect ratio)
   - Store variant to storage backend
5. Update MediaItem: set `width`, `height`, `variants` map, `status: :ready`
6. On error: set `status: :error`

SVG files: skip processing entirely, set status to `:ready` immediately with no variants.

## Web Layer

### Media Library Page

**Route:** `GET /admin/:slug/media`

**LiveView:** `NexusWeb.MediaLive.Index`

Full-page gallery showing all project images:
- Responsive thumbnail grid using `thumb` variants
- Drag-and-drop upload zone at the top
- Click-to-upload button
- Upload progress indicators
- Click thumbnail to expand details panel:
  - Preview (large variant)
  - Filename, dimensions, file size
  - Alt text input (editable, auto-saves)
  - Copy URL button (copies proxy URL)
  - Delete button with confirmation
- Status badges for pending/processing images

### Sidebar Nav Link

Add a "Media" link to the sidebar bottom nav in the project layout (alongside Members, API Keys, Settings):

```
┌─────────────────────┐
│ Members             │
│ Media               │  ← new
│ API Keys            │
│ Settings            │
└─────────────────────┘
```

Uses `hero-photo` icon.

### Media Picker Modal

**LiveComponent:** `NexusWeb.MediaLive.PickerComponent`

Reusable modal that can be opened from:
- Tiptap toolbar button
- Tiptap `/image` slash command
- Template `:image` field click

Shows:
- Thumbnail grid of project images (same as gallery)
- Upload zone (upload new and immediately select)
- Click to select → fires a callback/event with the selected media item

### Tiptap Integration

Three insertion methods:

1. **Drag-drop onto editor** — JS intercepts drop, uploads via LiveView `allow_upload`, inserts `<img>` with proxy URL after upload completes
2. **Toolbar button** — opens media picker modal, selected image inserted as tiptap image node
3. **Slash command `/image`** — opens same media picker modal

The tiptap image node stores the proxy URL (e.g. `/media/{project_id}/{id}_medium.jpg`). Default insertion uses the `medium` variant.

### Template `:image` Field Update

The existing `:image` template field changes from a URL text input to:
- Click to open media picker modal
- Selected image stores `media_item_id` in `template_data`
- Renders preview thumbnail
- Alt text from the media item
- Option to clear selection
- Fallback: still allows pasting an external URL

## Dependencies

New hex packages:
- `image` — image processing (libvips via Vix, no system install needed on most platforms)
- `ex_aws` — base AWS SDK
- `ex_aws_s3` — S3 API client

Existing packages used:
- `oban` + `ash_oban` — background processing
- `req` — HTTP client (if needed for S3 operations)

## API

MediaItem is exposed via the existing AshJsonApi router for headless CMS use cases:
- `GET /api/v1/media_items?filter[project_id]=...`
- `GET /api/v1/media_items/:id`
- `DELETE /api/v1/media_items/:id`
