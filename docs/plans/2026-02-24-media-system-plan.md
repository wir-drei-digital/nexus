# Media System Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add an image media system with upload, processing, storage (local + S3), proxy serving, gallery page, and tiptap integration.

**Architecture:** New `Nexus.Media` domain with `MediaItem` Ash resource. Storage abstraction layer delegates to local filesystem or S3. Oban job generates image variants (thumb/medium/large) on upload using the `image` library. Proxy controller at `/media/*` serves all images regardless of backend. Media picker LiveComponent reused across the gallery page, tiptap editor, and template image fields.

**Tech Stack:** Ash 3, Phoenix LiveView, `image` (libvips/Vix), `ex_aws_s3`, Oban, tiptap-phoenix

**Design doc:** `docs/plans/2026-02-24-media-system-design.md`

---

## Task 1: Add Dependencies

**Files:**
- Modify: `mix.exs:90` (add deps before closing bracket)
- Modify: `config/config.exs:15` (add `:media_processing` queue to Oban)

**Step 1: Add hex deps to mix.exs**

In `mix.exs`, add after line 90 (`{:mdex, "~> 0.6"}`):

```elixir
{:image, "~> 0.54"},
{:ex_aws, "~> 2.0"},
{:ex_aws_s3, "~> 2.0"}
```

**Step 2: Add Oban queue**

In `config/config.exs`, change line 15 from:

```elixir
queues: [default: 10],
```

to:

```elixir
queues: [default: 10, media_processing: 5],
```

**Step 3: Install deps**

Run: `mix deps.get`
Expected: All deps resolve successfully.

**Step 4: Compile**

Run: `mix compile`
Expected: Clean compilation, no warnings.

**Step 5: Commit**

```bash
git add mix.exs mix.lock config/config.exs
git commit -m "deps: add image, ex_aws, ex_aws_s3 for media system"
```

---

## Task 2: Storage Backend — Local

**Files:**
- Create: `lib/nexus/media/storage.ex`
- Create: `lib/nexus/media/storage/local.ex`
- Create: `test/nexus/media/storage_test.exs`

**Step 1: Write tests for local storage**

```elixir
# test/nexus/media/storage_test.exs
defmodule Nexus.Media.StorageTest do
  use ExUnit.Case, async: true

  alias Nexus.Media.Storage
  alias Nexus.Media.Storage.Local

  @test_dir Path.join(System.tmp_dir!(), "nexus_storage_test_#{System.unique_integer([:positive])}")

  setup do
    File.mkdir_p!(@test_dir)
    on_exit(fn -> File.rm_rf!(@test_dir) end)
    :ok
  end

  describe "Local.store/3" do
    test "stores and retrieves file content" do
      assert {:ok, "test/file.jpg"} = Local.store("test/file.jpg", "binary content", base_dir: @test_dir)
      assert {:ok, "binary content"} = Local.get("test/file.jpg", base_dir: @test_dir)
    end

    test "creates nested directories" do
      assert {:ok, _} = Local.store("a/b/c/deep.png", "data", base_dir: @test_dir)
      assert {:ok, "data"} = Local.get("a/b/c/deep.png", base_dir: @test_dir)
    end

    test "rejects path traversal" do
      assert {:error, :invalid_path} = Local.store("../escape.jpg", "data", base_dir: @test_dir)
      assert {:error, :invalid_path} = Local.get("../../etc/passwd", base_dir: @test_dir)
    end
  end

  describe "Local.delete/2" do
    test "deletes existing file" do
      {:ok, _} = Local.store("to_delete.jpg", "data", base_dir: @test_dir)
      assert :ok = Local.delete("to_delete.jpg", base_dir: @test_dir)
      assert {:error, :not_found} = Local.get("to_delete.jpg", base_dir: @test_dir)
    end

    test "returns ok for missing file" do
      assert :ok = Local.delete("nonexistent.jpg", base_dir: @test_dir)
    end
  end

  describe "Storage.url/1" do
    test "returns proxy URL" do
      assert "/media/project123/abc_thumb.jpg" = Storage.url("project123/abc_thumb.jpg")
    end
  end

  describe "Storage.generate_path/3" do
    test "generates path with extension from filename" do
      path = Storage.generate_path("proj-id", "item-id", "photo.jpg")
      assert path == "proj-id/item-id.jpg"
    end

    test "generates variant path" do
      path = Storage.generate_path("proj-id", "item-id", "photo.jpg", :thumb)
      assert path == "proj-id/item-id_thumb.jpg"
    end
  end

  describe "Storage.mime_type_from_path/1" do
    test "detects common image types" do
      assert "image/jpeg" = Storage.mime_type_from_path("photo.jpg")
      assert "image/jpeg" = Storage.mime_type_from_path("photo.jpeg")
      assert "image/png" = Storage.mime_type_from_path("image.png")
      assert "image/gif" = Storage.mime_type_from_path("anim.gif")
      assert "image/webp" = Storage.mime_type_from_path("modern.webp")
      assert "image/svg+xml" = Storage.mime_type_from_path("icon.svg")
    end
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `mix test test/nexus/media/storage_test.exs`
Expected: All tests fail (modules don't exist).

**Step 3: Implement Storage abstraction**

```elixir
# lib/nexus/media/storage.ex
defmodule Nexus.Media.Storage do
  @moduledoc """
  Abstraction layer for media file storage.
  Delegates to configured backend: Local (dev/test) or S3 (production).
  """

  alias Nexus.Media.Storage.Local

  def backend, do: Application.get_env(:nexus, :storage_backend, :local)

  def store(relative_path, content, opts \\ []) do
    case get_backend(opts) do
      :local -> Local.store(relative_path, content, opts)
      :s3 -> Nexus.Media.Storage.S3.store(relative_path, content, opts)
    end
  end

  def get(relative_path, opts \\ []) do
    case get_backend(opts) do
      :local -> Local.get(relative_path, opts)
      :s3 -> Nexus.Media.Storage.S3.get(relative_path, opts)
    end
  end

  def delete(relative_path, opts \\ []) do
    case get_backend(opts) do
      :local -> Local.delete(relative_path, opts)
      :s3 -> Nexus.Media.Storage.S3.delete(relative_path, opts)
    end
  end

  @doc "Returns the public proxy URL for a stored file."
  def url(relative_path), do: "/media/#{relative_path}"

  @doc "Generates a storage path for a media item."
  def generate_path(project_id, item_id, filename, variant \\ nil) do
    ext = Path.extname(filename)
    suffix = if variant, do: "_#{variant}", else: ""
    "#{project_id}/#{item_id}#{suffix}#{ext}"
  end

  @mime_types %{
    ".jpg" => "image/jpeg",
    ".jpeg" => "image/jpeg",
    ".png" => "image/png",
    ".gif" => "image/gif",
    ".webp" => "image/webp",
    ".svg" => "image/svg+xml"
  }

  @doc "Detects MIME type from file extension."
  def mime_type_from_path(path) do
    ext = path |> Path.extname() |> String.downcase()
    Map.get(@mime_types, ext, "application/octet-stream")
  end

  defp get_backend(opts), do: Keyword.get(opts, :backend, backend())
end
```

**Step 4: Implement Local backend**

```elixir
# lib/nexus/media/storage/local.ex
defmodule Nexus.Media.Storage.Local do
  @moduledoc "Local filesystem storage backend for media files."

  @default_base_dir "priv/static/uploads/media"

  def store(relative_path, content, opts \\ []) do
    base = base_dir(opts)
    full_path = Path.join(base, relative_path)

    with :ok <- validate_path(full_path, base) do
      full_path |> Path.dirname() |> File.mkdir_p!()
      File.write!(full_path, content)
      {:ok, relative_path}
    end
  end

  def get(relative_path, opts \\ []) do
    base = base_dir(opts)
    full_path = Path.join(base, relative_path)

    with :ok <- validate_path(full_path, base) do
      case File.read(full_path) do
        {:ok, content} -> {:ok, content}
        {:error, :enoent} -> {:error, :not_found}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  def delete(relative_path, opts \\ []) do
    base = base_dir(opts)
    full_path = Path.join(base, relative_path)

    with :ok <- validate_path(full_path, base) do
      case File.rm(full_path) do
        :ok -> :ok
        {:error, :enoent} -> :ok
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp base_dir(opts) do
    Keyword.get(opts, :base_dir, @default_base_dir)
  end

  defp validate_path(full_path, base) do
    expanded = Path.expand(full_path)
    expanded_base = Path.expand(base)

    if String.starts_with?(expanded, expanded_base <> "/") do
      :ok
    else
      {:error, :invalid_path}
    end
  end
end
```

**Step 5: Run tests**

Run: `mix test test/nexus/media/storage_test.exs`
Expected: All tests pass.

**Step 6: Commit**

```bash
git add lib/nexus/media/storage.ex lib/nexus/media/storage/local.ex test/nexus/media/storage_test.exs
git commit -m "feat: add media storage abstraction with local backend"
```

---

## Task 3: Storage Backend — S3

**Files:**
- Create: `lib/nexus/media/storage/s3.ex`

No tests for S3 — relies on ex_aws mocking or integration tests. The module follows the same interface as Local.

**Step 1: Implement S3 backend**

```elixir
# lib/nexus/media/storage/s3.ex
defmodule Nexus.Media.Storage.S3 do
  @moduledoc "S3-compatible storage backend for media files."

  def store(relative_path, content, opts \\ []) do
    key = s3_key(relative_path)
    content_type = Keyword.get(opts, :content_type, Nexus.Media.Storage.mime_type_from_path(relative_path))

    case ExAws.S3.put_object(bucket(), key, content, content_type: content_type)
         |> ExAws.request(aws_config()) do
      {:ok, _} -> {:ok, relative_path}
      {:error, reason} -> {:error, reason}
    end
  end

  def get(relative_path, _opts \\ []) do
    key = s3_key(relative_path)

    case ExAws.S3.get_object(bucket(), key) |> ExAws.request(aws_config()) do
      {:ok, %{body: body}} -> {:ok, body}
      {:error, {:http_error, 404, _}} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  def delete(relative_path, _opts \\ []) do
    key = s3_key(relative_path)

    case ExAws.S3.delete_object(bucket(), key) |> ExAws.request(aws_config()) do
      {:ok, _} -> :ok
      {:error, {:http_error, 404, _}} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp s3_key(relative_path) do
    prefix = s3_config()[:prefix] || "media"
    "#{prefix}/#{relative_path}"
  end

  defp bucket, do: s3_config()[:bucket]

  defp s3_config, do: Application.get_env(:nexus, :s3, [])

  defp aws_config do
    config = s3_config()

    base = [
      access_key_id: config[:access_key_id],
      secret_access_key: config[:secret_access_key],
      region: config[:region] || "auto"
    ]

    case config[:host] do
      nil -> base
      host -> Keyword.merge(base, host: host, scheme: config[:scheme] || "https://")
    end
  end
end
```

**Step 2: Add storage config to config files**

In `config/dev.exs`, add after line 72 (`config :nexus, dev_routes: true, ...`):

```elixir
config :nexus, :storage_backend, :local
```

In `config/test.exs`, add after line 5 (`config :ash, ...`):

```elixir
config :nexus, :storage_backend, :local
```

In `config/runtime.exs`, add after line 77 (after token_signing_secret block), inside the `if config_env() == :prod` block:

```elixir
  # Media storage
  config :nexus, :storage_backend,
    if(System.get_env("AWS_BUCKET"), do: :s3, else: :local)

  if bucket = System.get_env("AWS_BUCKET") do
    config :nexus, :s3,
      access_key_id: System.get_env("AWS_ACCESS_KEY_ID"),
      secret_access_key: System.get_env("AWS_SECRET_ACCESS_KEY"),
      region: System.get_env("AWS_REGION", "auto"),
      bucket: bucket,
      host: System.get_env("AWS_S3_HOST"),
      scheme: "https://",
      prefix: "media"
  end
```

**Step 3: Compile and run existing tests**

Run: `mix compile && mix test test/nexus/media/storage_test.exs`
Expected: All pass.

**Step 4: Commit**

```bash
git add lib/nexus/media/storage/s3.ex config/dev.exs config/test.exs config/runtime.exs
git commit -m "feat: add S3 storage backend and config for all environments"
```

---

## Task 4: MediaItem Ash Resource + Domain

**Files:**
- Create: `lib/nexus/media.ex` (domain)
- Create: `lib/nexus/media/media_item.ex` (resource)
- Modify: `config/config.exs:74` (add domain to ash_domains)
- Create: `test/nexus/media/media_item_test.exs`

**Step 1: Write tests for MediaItem resource**

```elixir
# test/nexus/media/media_item_test.exs
defmodule Nexus.Media.MediaItemTest do
  use Nexus.DataCase, async: true

  import Nexus.Fixtures

  setup do
    user = create_user()
    project = create_project(user)
    %{user: user, project: project}
  end

  describe "create" do
    test "creates a media item", %{user: user, project: project} do
      attrs = %{
        filename: "hero.jpg",
        file_path: "#{project.id}/test-id.jpg",
        mime_type: "image/jpeg",
        file_size: 12345,
        storage_backend: "local",
        project_id: project.id,
        uploaded_by_id: user.id
      }

      assert {:ok, item} = Nexus.Media.MediaItem.create(attrs, actor: user)
      assert item.filename == "hero.jpg"
      assert item.status == :pending
      assert item.mime_type == "image/jpeg"
      assert item.project_id == project.id
    end
  end

  describe "list_for_project" do
    test "returns items for a project", %{user: user, project: project} do
      create_media_item(project, user, %{filename: "a.jpg"})
      create_media_item(project, user, %{filename: "b.png"})

      assert {:ok, items} = Nexus.Media.MediaItem.list_for_project(project.id, actor: user)
      assert length(items) == 2
    end

    test "does not return items from other projects", %{user: user, project: project} do
      other_project = create_project(user, %{name: "Other", slug: unique_slug()})
      create_media_item(project, user)
      create_media_item(other_project, user)

      assert {:ok, items} = Nexus.Media.MediaItem.list_for_project(project.id, actor: user)
      assert length(items) == 1
    end
  end

  describe "update_alt_text" do
    test "updates alt text", %{user: user, project: project} do
      item = create_media_item(project, user)

      assert {:ok, updated} =
               Nexus.Media.MediaItem.update_alt_text(item, %{alt_text: "A sunset"}, actor: user)

      assert updated.alt_text == "A sunset"
    end
  end

  describe "destroy" do
    test "deletes a media item", %{user: user, project: project} do
      item = create_media_item(project, user)
      assert :ok = Nexus.Media.MediaItem.destroy(item, actor: user)
    end
  end

  describe "update_status" do
    test "sets status to ready with variants and dimensions", %{user: user, project: project} do
      item = create_media_item(project, user)

      assert {:ok, updated} =
               Nexus.Media.MediaItem.update_status(item, %{
                 status: :ready,
                 width: 1920,
                 height: 1080,
                 variants: %{"thumb" => "p/id_thumb.jpg", "medium" => "p/id_medium.jpg"}
               })

      assert updated.status == :ready
      assert updated.width == 1920
      assert updated.variants["thumb"] == "p/id_thumb.jpg"
    end
  end
end
```

**Step 2: Add `create_media_item` fixture**

In `test/support/fixtures.ex`, add:

```elixir
def create_media_item(project, user, attrs \\ %{}) do
  item_id = Ash.UUID.generate()

  params =
    Map.merge(
      %{
        filename: "test-#{System.unique_integer([:positive])}.jpg",
        file_path: "#{project.id}/#{item_id}.jpg",
        mime_type: "image/jpeg",
        file_size: 1024,
        storage_backend: "local",
        project_id: project.id,
        uploaded_by_id: user.id
      },
      attrs
    )

  Nexus.Media.MediaItem.create!(params, actor: user)
end
```

**Step 3: Create the domain**

```elixir
# lib/nexus/media.ex
defmodule Nexus.Media do
  use Ash.Domain,
    otp_app: :nexus,
    extensions: [AshJsonApi.Domain]

  json_api do
    prefix "/api/v1"
    log_errors? true
  end

  resources do
    resource Nexus.Media.MediaItem
  end
end
```

**Step 4: Register domain in config**

In `config/config.exs`, change line 74 from:

```elixir
ash_domains: [Nexus.Accounts, Nexus.Projects, Nexus.Content, Nexus.AI]
```

to:

```elixir
ash_domains: [Nexus.Accounts, Nexus.Projects, Nexus.Content, Nexus.Media, Nexus.AI]
```

**Step 5: Create the MediaItem resource**

```elixir
# lib/nexus/media/media_item.ex
defmodule Nexus.Media.MediaItem do
  use Ash.Resource,
    otp_app: :nexus,
    domain: Nexus.Media,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshJsonApi.Resource]

  postgres do
    table "media_items"
    repo Nexus.Repo
  end

  json_api do
    type "media_items"

    routes do
      base "/media_items"
      index :list_for_project, primary?: true
      get :read, route: "/:id"
      delete :destroy
    end
  end

  code_interface do
    define :create
    define :read
    define :list_for_project, args: [:project_id]
    define :update_alt_text
    define :update_status
    define :destroy
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true

      accept [
        :filename,
        :file_path,
        :mime_type,
        :file_size,
        :storage_backend,
        :project_id,
        :uploaded_by_id
      ]

      change set_attribute(:status, :pending)
    end

    read :list_for_project do
      argument :project_id, :uuid, allow_nil?: false
      filter expr(project_id == ^arg(:project_id))
      prepare build(sort: [inserted_at: :desc])
    end

    update :update_alt_text do
      accept [:alt_text]
    end

    update :update_status do
      accept [:status, :width, :height, :variants]
      require_atomic? false
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if expr(exists(project.memberships, user_id == ^actor(:id)))
    end

    policy action_type(:create) do
      authorize_if {Nexus.Projects.Checks.HasProjectRole, roles: [:admin, :editor]}
    end

    policy action([:update_alt_text]) do
      authorize_if expr(
                     exists(
                       project.memberships,
                       user_id == ^actor(:id) and role in [:admin, :editor]
                     )
                   )
    end

    policy action(:update_status) do
      authorize_if always()
    end

    policy action_type(:destroy) do
      authorize_if expr(exists(project.memberships, user_id == ^actor(:id) and role == :admin))
    end
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :filename, :string, allow_nil?: false, public?: true
    attribute :file_path, :string, allow_nil?: false, public?: true
    attribute :mime_type, :string, allow_nil?: false, public?: true
    attribute :file_size, :integer, allow_nil?: false, public?: true
    attribute :width, :integer, public?: true
    attribute :height, :integer, public?: true
    attribute :alt_text, :string, public?: true

    attribute :variants, :map do
      default %{}
      public? true
    end

    attribute :storage_backend, :string do
      allow_nil? false
      public? true
    end

    attribute :status, :atom do
      constraints one_of: [:pending, :processing, :ready, :error]
      default :pending
      allow_nil? false
      public? true
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :project, Nexus.Projects.Project, allow_nil?: false
    belongs_to :uploaded_by, Nexus.Accounts.User, allow_nil?: false
  end
end
```

**Step 6: Generate and run migration**

Run: `mix ash_postgres.generate_migrations --name add_media_items`
Then: `mix ash.setup`

**Step 7: Run tests**

Run: `mix test test/nexus/media/media_item_test.exs`
Expected: All tests pass.

**Step 8: Run full test suite**

Run: `mix test`
Expected: All existing tests still pass.

**Step 9: Commit**

```bash
git add lib/nexus/media.ex lib/nexus/media/media_item.ex config/config.exs test/nexus/media/media_item_test.exs test/support/fixtures.ex priv/repo/migrations/ priv/resource_snapshots/
git commit -m "feat: add MediaItem resource with Nexus.Media domain"
```

---

## Task 5: Media Proxy Controller

**Files:**
- Create: `lib/nexus_web/controllers/media_controller.ex`
- Modify: `lib/nexus_web/router.ex` (add `/media` route)
- Create: `test/nexus_web/controllers/media_controller_test.exs`

**Step 1: Write tests**

```elixir
# test/nexus_web/controllers/media_controller_test.exs
defmodule NexusWeb.MediaControllerTest do
  use NexusWeb.ConnCase, async: true

  alias Nexus.Media.Storage

  @test_content <<0xFF, 0xD8, 0xFF, 0xE0>> <> "fake jpeg data"

  setup do
    # Store a test file
    path = "test-project/test-file.jpg"
    {:ok, _} = Storage.store(path, @test_content)
    on_exit(fn -> Storage.delete(path) end)
    %{path: path}
  end

  test "serves an existing file with correct headers", %{conn: conn, path: path} do
    conn = get(conn, "/media/#{path}")

    assert conn.status == 200
    assert get_resp_header(conn, "content-type") == ["image/jpeg"]
    assert get_resp_header(conn, "cache-control") == ["public, max-age=31536000, immutable"]
    assert conn.resp_body == @test_content
  end

  test "returns 404 for missing file", %{conn: conn} do
    conn = get(conn, "/media/nonexistent/missing.jpg")
    assert conn.status == 404
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `mix test test/nexus_web/controllers/media_controller_test.exs`
Expected: Fail (controller doesn't exist).

**Step 3: Implement controller**

```elixir
# lib/nexus_web/controllers/media_controller.ex
defmodule NexusWeb.MediaController do
  use NexusWeb, :controller

  alias Nexus.Media.Storage

  def show(conn, %{"path" => path_parts}) do
    relative_path = Path.join(path_parts)

    case Storage.get(relative_path) do
      {:ok, content} ->
        content_type = Storage.mime_type_from_path(relative_path)

        conn
        |> put_resp_header("content-type", content_type)
        |> put_resp_header("cache-control", "public, max-age=31536000, immutable")
        |> put_resp_header("etag", etag(relative_path))
        |> send_resp(200, content)

      {:error, _} ->
        send_resp(conn, 404, "Not found")
    end
  end

  defp etag(path), do: "\"#{Base.encode16(:crypto.hash(:md5, path), case: :lower)}\""
end
```

**Step 4: Add route**

In `lib/nexus_web/router.ex`, add before the authenticated scope (before line 36):

```elixir
# Public media proxy — no auth required
scope "/media", NexusWeb do
  pipe_through []
  get "/*path", MediaController, :show
end
```

**Step 5: Run tests**

Run: `mix test test/nexus_web/controllers/media_controller_test.exs`
Expected: All pass.

**Step 6: Run full test suite**

Run: `mix test`
Expected: All pass.

**Step 7: Commit**

```bash
git add lib/nexus_web/controllers/media_controller.ex lib/nexus_web/router.ex test/nexus_web/controllers/media_controller_test.exs
git commit -m "feat: add media proxy controller at /media/*"
```

---

## Task 6: Image Processor (Oban Job)

**Files:**
- Create: `lib/nexus/media/processor.ex`
- Create: `test/nexus/media/processor_test.exs`

**Step 1: Write tests**

```elixir
# test/nexus/media/processor_test.exs
defmodule Nexus.Media.ProcessorTest do
  use Nexus.DataCase, async: true
  use Oban.Testing, repo: Nexus.Repo

  import Nexus.Fixtures

  alias Nexus.Media.{Processor, Storage}

  @variant_sizes Processor.variant_sizes()

  setup do
    user = create_user()
    project = create_project(user)
    %{user: user, project: project}
  end

  describe "process/1 with a real image" do
    test "generates variants and updates media item", %{user: user, project: project} do
      # Create a real test image using the image library
      {:ok, img} = Image.new(1920, 1080, color: :green)
      {:ok, binary} = Image.write(img, :memory, suffix: ".jpg")

      file_path = Storage.generate_path(project.id, "test-proc-id", "photo.jpg")
      {:ok, _} = Storage.store(file_path, binary)
      on_exit(fn -> cleanup_files(project.id, "test-proc-id", ".jpg") end)

      item =
        create_media_item(project, user, %{
          filename: "photo.jpg",
          file_path: file_path,
          file_size: byte_size(binary)
        })

      assert {:ok, updated} = Processor.process(item)
      assert updated.status == :ready
      assert updated.width == 1920
      assert updated.height == 1080
      assert Map.has_key?(updated.variants, "thumb")
      assert Map.has_key?(updated.variants, "medium")
      assert Map.has_key?(updated.variants, "large")
    end

    test "skips variants larger than original", %{user: user, project: project} do
      {:ok, img} = Image.new(200, 150, color: :blue)
      {:ok, binary} = Image.write(img, :memory, suffix: ".jpg")

      file_path = Storage.generate_path(project.id, "test-small-id", "small.jpg")
      {:ok, _} = Storage.store(file_path, binary)
      on_exit(fn -> cleanup_files(project.id, "test-small-id", ".jpg") end)

      item =
        create_media_item(project, user, %{
          filename: "small.jpg",
          file_path: file_path,
          file_size: byte_size(binary)
        })

      assert {:ok, updated} = Processor.process(item)
      assert updated.status == :ready
      assert updated.width == 200
      assert updated.variants == %{}
    end

    test "handles SVGs by skipping processing", %{user: user, project: project} do
      svg = ~s(<svg xmlns="http://www.w3.org/2000/svg" width="100" height="100"><circle r="50"/></svg>)
      file_path = Storage.generate_path(project.id, "test-svg-id", "icon.svg")
      {:ok, _} = Storage.store(file_path, svg)
      on_exit(fn -> Storage.delete(file_path) end)

      item =
        create_media_item(project, user, %{
          filename: "icon.svg",
          file_path: file_path,
          mime_type: "image/svg+xml",
          file_size: byte_size(svg)
        })

      assert {:ok, updated} = Processor.process(item)
      assert updated.status == :ready
      assert updated.variants == %{}
    end
  end

  defp cleanup_files(project_id, item_id, ext) do
    Storage.delete("#{project_id}/#{item_id}#{ext}")

    for {name, _} <- @variant_sizes do
      Storage.delete("#{project_id}/#{item_id}_#{name}#{ext}")
    end
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `mix test test/nexus/media/processor_test.exs`
Expected: Fail.

**Step 3: Implement Processor**

```elixir
# lib/nexus/media/processor.ex
defmodule Nexus.Media.Processor do
  @moduledoc """
  Processes uploaded images: extracts metadata and generates variants.
  Runs as an Oban job in the :media_processing queue.
  """

  use Oban.Worker, queue: :media_processing, max_attempts: 3

  alias Nexus.Media.Storage

  require Logger

  @variant_sizes [{"thumb", 300}, {"medium", 800}, {"large", 1600}]

  def variant_sizes, do: @variant_sizes

  @doc "Process a media item: extract metadata and generate variants."
  def process(%{id: id} = _media_item) do
    item = Nexus.Media.MediaItem.read!(id, authorize?: false)
    do_process(item)
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"media_item_id" => id}}) do
    case Ash.get(Nexus.Media.MediaItem, id, authorize?: false) do
      {:ok, item} ->
        case do_process(item) do
          {:ok, _} -> :ok
          {:error, reason} -> {:error, reason}
        end

      {:error, _} ->
        :ok
    end
  end

  defp do_process(item) do
    # Mark as processing
    Nexus.Media.MediaItem.update_status(item, %{status: :processing}, authorize?: false)

    if item.mime_type == "image/svg+xml" do
      Nexus.Media.MediaItem.update_status(
        item,
        %{status: :ready, variants: %{}},
        authorize?: false
      )
    else
      case process_raster_image(item) do
        {:ok, result} ->
          Nexus.Media.MediaItem.update_status(item, result, authorize?: false)

        {:error, reason} ->
          Logger.error("Media processing failed for #{item.id}: #{inspect(reason)}")

          Nexus.Media.MediaItem.update_status(
            item,
            %{status: :error},
            authorize?: false
          )
      end
    end
  end

  defp process_raster_image(item) do
    with {:ok, content} <- Storage.get(item.file_path),
         {:ok, image} <- Image.from_binary(content) do
      {width, height, _} = Image.shape(image)
      ext = Path.extname(item.file_path)
      base_path = String.replace_suffix(item.file_path, ext, "")

      variants =
        @variant_sizes
        |> Enum.filter(fn {_name, max_width} -> width > max_width end)
        |> Enum.reduce(%{}, fn {name, max_width}, acc ->
          variant_path = "#{base_path}_#{name}#{ext}"

          case generate_variant(image, max_width, variant_path, ext) do
            :ok -> Map.put(acc, name, variant_path)
            {:error, reason} ->
              Logger.warning("Failed to generate #{name} variant: #{inspect(reason)}")
              acc
          end
        end)

      {:ok, %{status: :ready, width: width, height: height, variants: variants}}
    end
  end

  defp generate_variant(image, max_width, variant_path, ext) do
    with {:ok, resized} <- Image.thumbnail(image, max_width),
         {:ok, binary} <- Image.write(resized, :memory, suffix: ext) do
      case Storage.store(variant_path, binary) do
        {:ok, _} -> :ok
        error -> error
      end
    end
  end
end
```

**Step 4: Run tests**

Run: `mix test test/nexus/media/processor_test.exs`
Expected: All pass.

**Step 5: Commit**

```bash
git add lib/nexus/media/processor.ex test/nexus/media/processor_test.exs
git commit -m "feat: add image processor with variant generation"
```

---

## Task 7: Sidebar Nav Link + Media Route

**Files:**
- Modify: `lib/nexus_web/components/layouts.ex:144-160` (add Media nav link)
- Modify: `lib/nexus_web/router.ex:48` (add media route)

**Step 1: Add the Media nav link to sidebar**

In `lib/nexus_web/components/layouts.ex`, in the bottom nav section (around line 144), add the Media link after Members:

Change the `<nav>` section from:

```html
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
```

to:

```html
<nav class="border-t border-base-300 p-2 space-y-px">
  <.sidebar_nav_link
    href={~p"/admin/#{@project.slug}/media"}
    icon="hero-photo"
    label="Media"
  />
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
```

**Step 2: Add route**

In `lib/nexus_web/router.ex`, add inside the `ash_authentication_live_session` block (after line 48):

```elixir
live "/admin/:slug/media", MediaLive.Index, :index
```

**Step 3: Create stub LiveView** (so routes compile — full implementation in Task 8)

```elixir
# lib/nexus_web/live/media_live/index.ex
defmodule NexusWeb.MediaLive.Index do
  use NexusWeb, :live_view

  on_mount {NexusWeb.LiveUserAuth, :live_user_required}
  on_mount {NexusWeb.ProjectScope, :default}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Media")
     |> assign(:breadcrumbs, [{"Media", nil}])
     |> assign(:media_items, [])}
  end

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
      breadcrumbs={@breadcrumbs}
    >
      <div class="p-6">
        <h1 class="text-2xl font-bold">Media Library</h1>
        <p class="text-base-content/60 mt-2">Coming soon...</p>
      </div>
    </Layouts.project>
    """
  end
end
```

**Step 4: Compile and verify**

Run: `mix compile`
Expected: No errors.

**Step 5: Run full test suite**

Run: `mix test`
Expected: All pass.

**Step 6: Commit**

```bash
git add lib/nexus_web/components/layouts.ex lib/nexus_web/router.ex lib/nexus_web/live/media_live/index.ex
git commit -m "feat: add Media sidebar link and route with stub page"
```

---

## Task 8: Media Library Page (Full Implementation)

**Files:**
- Modify: `lib/nexus_web/live/media_live/index.ex`

This is the full gallery page with uploads, thumbnail grid, detail panel, and delete.

**Step 1: Implement the full MediaLive.Index LiveView**

Replace the stub with the full implementation. Key features:
- `allow_upload/3` for `:media_uploads` accepting images up to 20MB, max 10 at once
- `handle_event("save_uploads", ...)` — consumes uploads, stores via `Storage`, creates `MediaItem` records, enqueues Oban processor jobs
- Thumbnail grid showing `thumb` variant URLs (fall back to original if no thumb yet)
- Click thumbnail to select → shows detail panel with preview, metadata, alt text edit, copy URL, delete
- Drag-and-drop zone at top
- Upload progress indicators per file
- `handle_event("delete_media_item", ...)` — deletes record + storage files
- `handle_event("update_alt_text", ...)` — saves alt text with debounce
- Auto-refresh items after upload completes (poll or PubSub — simple approach: reload after upload)

The LiveView should use `Phoenix.LiveView.upload` for the upload flow. When uploads complete:
1. `consume_uploaded_entries` reads the temp file
2. Generate storage path via `Storage.generate_path/3`
3. Store original via `Storage.store/2`
4. Create `MediaItem` record (status: :pending)
5. Enqueue `Processor` Oban job: `%{"media_item_id" => item.id} |> Nexus.Media.Processor.new() |> Oban.insert()`

For the delete flow:
1. Delete all variant files from storage
2. Delete original file from storage
3. Destroy the `MediaItem` record

**Implementation note:** The full HEEx template will include the upload zone, grid, and detail panel. Use daisyUI classes consistent with the existing codebase. Use `hero-*` icons.

**Step 2: Verify manually**

Run: `mix phx.server`
Navigate to: `http://localhost:4010/admin/{slug}/media`
Expected: See the media library page with upload zone and empty grid.

**Step 3: Test upload flow manually**

Upload an image, verify it appears in the grid, click to see details, delete it.

**Step 4: Commit**

```bash
git add lib/nexus_web/live/media_live/index.ex
git commit -m "feat: implement media library page with upload, gallery, and detail panel"
```

---

## Task 9: Media Picker Component

**Files:**
- Create: `lib/nexus_web/live/media_live/picker_component.ex`

A reusable `Phoenix.LiveComponent` that shows a modal with:
- Thumbnail grid of project media items
- Upload zone (upload and select in one step)
- Click to select → sends `{:media_selected, media_item}` message to parent

**Attributes:**
- `id` — required (for LiveComponent targeting)
- `project` — the current project
- `current_user` — for authorization
- `target` — the parent LiveView pid or `{module, id}` to send selection events to

**Events emitted:**
- `send(self(), {:media_selected, media_item, meta})` where `meta` contains the field key or editor context

**Usage from parent LiveView:**

```heex
<.live_component
  :if={@show_media_picker}
  module={NexusWeb.MediaLive.PickerComponent}
  id="media-picker"
  project={@project}
  current_user={@current_user}
  target={@media_picker_target}
/>
```

**Step 1: Implement the component**

The component manages its own upload lifecycle (separate from the parent). It loads media items on mount, renders a modal overlay with grid + upload zone, and emits selection events.

**Step 2: Verify manually**

Will be testable after Task 10 (tiptap integration) or Task 11 (image field).

**Step 3: Commit**

```bash
git add lib/nexus_web/live/media_live/picker_component.ex
git commit -m "feat: add reusable media picker modal component"
```

---

## Task 10: Template `:image` Field — Media Picker Integration

**Files:**
- Modify: `lib/nexus_web/live/page_live/edit.ex:1301-1326` (image field template)
- Modify: `lib/nexus_web/live/page_live/edit.ex` (add media picker state + events)

**Step 1: Update the page editor to support media picker**

Add to mount assigns:
- `:show_media_picker` — boolean, false initially
- `:media_picker_target` — `%{field_key: key}` or `%{editor_key: key}`

Add event handlers:
- `handle_event("open_media_picker", %{"field" => key}, socket)` — opens picker for a template field
- `handle_info({:media_selected, item, %{field_key: key}}, socket)` — receives selection, updates template_data with the media URL, closes picker
- `handle_event("close_media_picker", _, socket)` — closes picker

**Step 2: Update the `:image` template field rendering**

Change from URL input to a clickable media selector. The field stores the proxy URL (e.g., `/media/{project_id}/{id}_large.jpg`) in template_data — keeping it a string so existing rendering and API output still work.

```heex
<div>
  <label class="text-xs font-medium text-base-content/60 mb-1 block">
    {@field.label}
    <span :if={@field.required} class="text-error">*</span>
  </label>
  <div
    :if={@value && @value != ""}
    class="relative group rounded-box overflow-hidden mb-2"
  >
    <img src={@value} class="max-h-48 rounded-box object-cover w-full" />
    <div class="absolute inset-0 bg-black/50 opacity-0 group-hover:opacity-100 flex items-center justify-center gap-2 transition-opacity">
      <button
        type="button"
        phx-click="open_media_picker"
        phx-value-field={@key}
        class="btn btn-sm btn-ghost text-white"
      >
        Change
      </button>
      <button
        type="button"
        phx-click="clear_image_field"
        phx-value-field={@key}
        class="btn btn-sm btn-ghost text-white"
      >
        Remove
      </button>
    </div>
  </div>
  <button
    :if={!@value || @value == ""}
    type="button"
    phx-click="open_media_picker"
    phx-value-field={@key}
    class="btn btn-outline btn-sm w-full"
  >
    <.icon name="hero-photo" class="size-4" /> Select image
  </button>
</div>
```

**Step 3: Update renderer**

In `lib/nexus/content/templates/renderer.ex`, update the `:image` render_field to also accept `/media/` paths (they're relative URLs, not http/https). Change the `safe_scheme?` check:

The image field now stores proxy URLs like `/media/proj/id_large.jpg`. Update the renderer to accept these alongside external URLs:

```elixir
defp render_field(%Field{key: key, type: :image}, value) when is_binary(value) do
  if value != "" && (safe_scheme?(value, @allowed_image_schemes) || String.starts_with?(value, "/media/")) do
    ~s(<section data-field="#{key}" data-type="image"><img src="#{escape(value)}" alt=""></section>)
  else
    ""
  end
end
```

**Step 4: Verify manually**

Edit a blog post template, click "Select image" on the hero_image field, select from media picker, verify image appears.

**Step 5: Commit**

```bash
git add lib/nexus_web/live/page_live/edit.ex lib/nexus/content/templates/renderer.ex
git commit -m "feat: integrate media picker with template image fields"
```

---

## Task 11: Tiptap Image Upload Integration

**Files:**
- Create: `assets/js/hooks/media_upload.js` (JS hook for drag-drop + toolbar)
- Modify: `assets/js/app.js:36` (register new hook)
- Modify: `lib/nexus_web/live/page_live/edit.ex` (upload handling + tiptap events)

**Step 1: Create the JS hook**

The hook manages:
- Intercepting image drag-drop onto the tiptap editor
- Listening for `phx:media_uploaded` events to insert the image into tiptap
- Toolbar button click → sends `phx-click="open_media_picker"` with editor context

The drag-drop flow:
1. User drops an image onto the editor area
2. JS hook catches the `drop` event, creates a `File` input
3. Hook triggers a LiveView upload via the upload input
4. Server processes upload, sends `push_event("media_uploaded", %{url: url, editor_key: key})`
5. JS hook receives event, inserts `<img>` into tiptap at cursor position

**Step 2: Register hook in app.js**

In `assets/js/app.js`, add import and register in hooks object.

**Step 3: Add upload handling to page editor**

Add `allow_upload(:media_upload, ...)` to the page editor mount. Add `handle_event("media_upload_to_editor", ...)` to process uploads from the editor.

**Step 4: Handle media picker for editor context**

When media picker is opened from tiptap toolbar/slash command, the `target` metadata includes `%{editor_key: key}`. On selection, instead of updating template_data, push an event to insert the image into the tiptap editor.

**Step 5: Verify manually**

- Drag an image into the tiptap editor → image appears inline
- Use toolbar button → picker opens → select image → image inserted
- Use `/image` slash command → picker opens → select image → image inserted

**Step 6: Commit**

```bash
git add assets/js/hooks/media_upload.js assets/js/app.js lib/nexus_web/live/page_live/edit.ex
git commit -m "feat: integrate image upload and picker with tiptap editor"
```

---

## Task 12: Delete Cleanup + Storage Cascade

**Files:**
- Create: `lib/nexus/media/changes/delete_files.ex`
- Modify: `lib/nexus/media/media_item.ex` (add change to destroy action)

**Step 1: Create the Ash change for delete cleanup**

```elixir
# lib/nexus/media/changes/delete_files.ex
defmodule Nexus.Media.Changes.DeleteFiles do
  @moduledoc "Deletes stored files (original + variants) when a MediaItem is destroyed."

  use Ash.Resource.Change

  alias Nexus.Media.Storage

  require Logger

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      item = changeset.data

      # Delete original
      case Storage.delete(item.file_path) do
        :ok -> :ok
        {:error, reason} -> Logger.warning("Failed to delete original #{item.file_path}: #{inspect(reason)}")
      end

      # Delete variants
      for {_name, variant_path} <- item.variants || %{} do
        case Storage.delete(variant_path) do
          :ok -> :ok
          {:error, reason} -> Logger.warning("Failed to delete variant #{variant_path}: #{inspect(reason)}")
        end
      end

      changeset
    end)
  end
end
```

**Step 2: Add change to destroy action in MediaItem**

In `lib/nexus/media/media_item.ex`, change the destroy action from:

```elixir
defaults [:read, :destroy]
```

to:

```elixir
defaults [:read]

destroy :destroy do
  primary? true
  change Nexus.Media.Changes.DeleteFiles
end
```

**Step 3: Run tests**

Run: `mix test`
Expected: All pass.

**Step 4: Commit**

```bash
git add lib/nexus/media/changes/delete_files.ex lib/nexus/media/media_item.ex
git commit -m "feat: cascade delete storage files on MediaItem destroy"
```

---

## Task 13: Final Integration — Precommit + Manual Testing

**Step 1: Run precommit**

Run: `mix precommit`
Expected: Compile (no warnings), format clean, all tests pass.

**Step 2: Manual end-to-end testing checklist**

Run: `mix phx.server` and verify:

1. [ ] Media link visible in sidebar
2. [ ] Media library page loads at `/admin/:slug/media`
3. [ ] Upload images via drag-drop on media page
4. [ ] Upload images via file picker button
5. [ ] Thumbnails appear in grid after processing
6. [ ] Click thumbnail shows detail panel with preview
7. [ ] Edit alt text and verify it saves
8. [ ] Copy URL button works
9. [ ] Delete image removes from grid and storage
10. [ ] Open page editor, click "Select image" on image field
11. [ ] Media picker modal opens, select image, field updates
12. [ ] Drag image into tiptap editor, image appears inline
13. [ ] Images serve correctly via `/media/*` proxy URL
14. [ ] Images show in published page content (via renderer)

**Step 3: Commit any fixes**

```bash
git add -A
git commit -m "fix: address integration issues from manual testing"
```

---

## Key Reference Files

| What | Where |
|------|-------|
| Ash resource pattern | `lib/nexus/content/page.ex` |
| Domain pattern | `lib/nexus/content.ex` |
| Layout/sidebar | `lib/nexus_web/components/layouts.ex:64-161` |
| Page editor | `lib/nexus_web/live/page_live/edit.ex` |
| Template image field | `lib/nexus_web/live/page_live/edit.ex:1301-1326` |
| Renderer | `lib/nexus/content/templates/renderer.ex:74-80` |
| Test fixtures | `test/support/fixtures.ex` |
| Router | `lib/nexus_web/router.ex` |
| JS hooks | `assets/js/app.js` |
| Oban config | `config/config.exs:12-17` |
| Omnios storage reference | `/Users/daniel/Development/omnios/lib/omnios/files/storage.ex` |
| Omnios local backend | `/Users/daniel/Development/omnios/lib/omnios/files/storage/local.ex` |
| Omnios S3 backend | `/Users/daniel/Development/omnios/lib/omnios/files/storage/s3.ex` |
| Omnios upload flow | `/Users/daniel/Development/omnios/lib/omnios_web/live/chat_live/components/library/files_sidebar_component.ex` |
