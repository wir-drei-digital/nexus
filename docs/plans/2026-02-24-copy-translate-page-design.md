# Copy/Translate Page Content Between Languages

## Problem

Users need to populate pages across multiple languages. Currently each locale's content must be entered manually from scratch. This is tedious when the source content already exists in another language.

## Solution

Add a sidebar "Actions" section to the page editor that lets users copy all content from a source locale into the currently selected locale, optionally translating text fields via LLM.

## Design Decisions

- **Single LLM call** for all translatable fields (not per-field) — gives the LLM full page context for consistent translations, is faster, and cheaper.
- **Target = current locale tab** — user navigates to the target locale, then copies from a source.
- **Source defaults to project default locale** (e.g., "en").
- **Auto-translate checkbox** (checked by default) — when unchecked, all fields are copied as-is without LLM.
- **Confirmation dialog** if target locale already has content — version history serves as safety net.
- **Translate everything** including SEO fields (title, meta_description, og_title, og_description).

## Field Classification

**Translatable** (sent to LLM when auto-translate is on):
- Template fields: `:text`, `:textarea`, `:rich_text`
- SEO fields: `title`, `meta_description`, `og_title`, `og_description`

**Direct copy** (always copied as-is):
- Template fields: `:image`, `:url`, `:number`, `:toggle`, `:select`
- SEO fields: `meta_keywords`, `og_image_url`

## UI Design

### Sidebar "Actions" Section

Located below the existing SEO section in the page editor sidebar:

- **Source language dropdown** — lists all `project.available_locales` except current locale. Defaults to `project.default_locale`. Shows human-readable locale names.
- **"Auto translate" checkbox** — checked by default. Controls whether text fields go through LLM translation.
- **"Copy from [source]" button** — triggers the action. Disabled while processing. Shows loading spinner.
- **Confirmation dialog** — shown if target locale has existing content: "This will overwrite existing content in [target locale]. Version history will preserve the current content."

## Backend

### New `translate_content` Action (Assistant resource)

**Arguments:**
- `content` — map of field key → value (only translatable fields)
- `source_locale` — string (e.g., "en")
- `target_locale` — string (e.g., "de")
- `field_types` — map of field key → type (for context about what each field is)

**Returns:** `{:ok, translated_map}` — same keys, translated values.

**Implementation (`AI.Helpers.translate_content_impl`):**
1. Convert rich_text fields to markdown via `ProseMirror` module
2. Build single LLM prompt: translate all fields from source to target, return JSON with same keys
3. Parse LLM JSON response
4. Convert markdown results back to ProseMirror JSON for rich_text fields
5. Return translated map

## LiveView Flow

### New Assigns
- `copy_source_locale` — selected source locale (default: project default locale)
- `auto_translate` — boolean (default: true)
- `copying_content` — boolean loading state

### Events
- `"update_copy_source"` — updates source locale dropdown
- `"toggle_auto_translate"` — toggles checkbox
- `"copy_content"` — initiates flow (shows confirmation if target has content)
- `"confirm_copy_content"` — executes after confirmation

### Execution Flow
1. Load source version: `PageVersion.current(page_id, source_locale)`
2. Classify fields into translatable vs direct-copy
3. If **auto_translate ON**:
   - Send translatable fields to `Assistant.translate_content` as async task
   - On completion, merge translated fields with direct-copied fields
   - Update form changeset + template_data
   - Push events to update TipTap editors in browser
   - Trigger auto-save
4. If **auto_translate OFF**:
   - Copy all fields directly from source version (synchronous)
   - Update form + template_data
   - Push events to update TipTap editors
   - Trigger auto-save
