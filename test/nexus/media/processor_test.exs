defmodule Nexus.Media.ProcessorTest do
  use Nexus.DataCase, async: true
  use Oban.Testing, repo: Nexus.Repo

  import Nexus.Fixtures
  alias Nexus.Media.{Processor, Storage}

  setup do
    user = create_user()
    project = create_project(user)
    %{user: user, project: project}
  end

  defp create_test_image(width, height) do
    {:ok, img} = Image.new(width, height, color: :green)
    {:ok, binary} = Image.write(img, :memory, suffix: ".jpg")
    binary
  end

  defp store_and_create_item(project, user, binary, attrs \\ %{}) do
    item_id = Ash.UUID.generate()
    file_path = "#{project.id}/#{item_id}.jpg"
    {:ok, _} = Storage.store(file_path, binary)

    item =
      create_media_item(
        project,
        user,
        %{
          file_path: file_path,
          file_size: byte_size(binary)
        }
        |> Map.merge(attrs)
      )

    {item, file_path}
  end

  defp cleanup_files(file_path, variants) do
    Storage.delete(file_path)

    Enum.each(variants, fn {_name, path} ->
      Storage.delete(path)
    end)
  end

  describe "process/1" do
    test "generates variants and updates media item for large image", ctx do
      binary = create_test_image(1920, 1080)
      {item, file_path} = store_and_create_item(ctx.project, ctx.user, binary)

      assert :ok = Processor.process(item)

      updated = Ash.get!(Nexus.Media.MediaItem, item.id, authorize?: false)
      assert updated.status == :ready
      assert updated.width == 1920
      assert updated.height == 1080

      assert Map.has_key?(updated.variants, "thumb")
      assert Map.has_key?(updated.variants, "medium")
      assert Map.has_key?(updated.variants, "large")

      # Verify variant files exist in storage
      Enum.each(updated.variants, fn {_name, path} ->
        assert {:ok, _content} = Storage.get(path)
      end)

      cleanup_files(file_path, updated.variants)
    end

    test "skips variants larger than original", ctx do
      binary = create_test_image(200, 150)
      {item, file_path} = store_and_create_item(ctx.project, ctx.user, binary)

      assert :ok = Processor.process(item)

      updated = Ash.get!(Nexus.Media.MediaItem, item.id, authorize?: false)
      assert updated.status == :ready
      assert updated.width == 200
      assert updated.height == 150
      assert updated.variants == %{}

      cleanup_files(file_path, %{})
    end

    test "generates only applicable variants for medium image", ctx do
      binary = create_test_image(500, 400)
      {item, file_path} = store_and_create_item(ctx.project, ctx.user, binary)

      assert :ok = Processor.process(item)

      updated = Ash.get!(Nexus.Media.MediaItem, item.id, authorize?: false)
      assert updated.status == :ready
      assert updated.width == 500
      assert updated.height == 400

      # Only thumb (300) should be generated since 500 > 300
      assert Map.has_key?(updated.variants, "thumb")
      refute Map.has_key?(updated.variants, "medium")
      refute Map.has_key?(updated.variants, "large")

      cleanup_files(file_path, updated.variants)
    end

    test "handles SVGs by setting ready with no variants", ctx do
      svg_content =
        ~s(<svg xmlns="http://www.w3.org/2000/svg" width="100" height="100"><circle cx="50" cy="50" r="40"/></svg>)

      item_id = Ash.UUID.generate()
      file_path = "#{ctx.project.id}/#{item_id}.svg"
      {:ok, _} = Storage.store(file_path, svg_content)

      item =
        create_media_item(ctx.project, ctx.user, %{
          filename: "icon.svg",
          file_path: file_path,
          mime_type: "image/svg+xml",
          file_size: byte_size(svg_content)
        })

      assert :ok = Processor.process(item)

      updated = Ash.get!(Nexus.Media.MediaItem, item.id, authorize?: false)
      assert updated.status == :ready
      assert updated.variants == %{}

      Storage.delete(file_path)
    end

    test "sets status to error on failure", ctx do
      # Create a media item with a non-existent file path
      item =
        create_media_item(ctx.project, ctx.user, %{
          file_path: "#{ctx.project.id}/nonexistent.jpg"
        })

      assert {:error, _reason} = Processor.process(item)

      updated = Ash.get!(Nexus.Media.MediaItem, item.id, authorize?: false)
      assert updated.status == :error
    end
  end

  describe "perform/1 (Oban integration)" do
    test "enqueues and performs job for a media item", ctx do
      binary = create_test_image(400, 300)
      {item, file_path} = store_and_create_item(ctx.project, ctx.user, binary)

      assert {:ok, _job} = Processor.enqueue(item)
      assert_enqueued(worker: Processor, args: %{media_item_id: item.id})

      # Manually perform the job
      assert :ok = perform_job(Processor, %{media_item_id: item.id})

      updated = Ash.get!(Nexus.Media.MediaItem, item.id, authorize?: false)
      assert updated.status == :ready
      assert updated.width == 400
      assert updated.height == 300

      # Only thumb should exist (400 > 300)
      assert Map.has_key?(updated.variants, "thumb")

      cleanup_files(file_path, updated.variants)
    end
  end
end
