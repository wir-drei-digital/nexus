defmodule Nexus.Media.StorageTest do
  use ExUnit.Case, async: true

  alias Nexus.Media.Storage
  alias Nexus.Media.Storage.Local

  @test_content "fake image binary content"

  setup do
    # Use a unique temp directory per test to avoid conflicts
    base_dir =
      Path.join(System.tmp_dir!(), "nexus_storage_test_#{System.unique_integer([:positive])}")

    File.mkdir_p!(base_dir)

    on_exit(fn -> File.rm_rf!(base_dir) end)

    %{base_dir: base_dir}
  end

  describe "Local.store/3" do
    test "stores file content and returns {:ok, relative_path}", %{base_dir: base_dir} do
      path = "project1/item1.jpg"

      assert {:ok, ^path} = Local.store(path, @test_content, base_dir: base_dir)
      assert File.read!(Path.join(base_dir, path)) == @test_content
    end

    test "creates nested directories automatically", %{base_dir: base_dir} do
      path = "deep/nested/dir/image.png"

      assert {:ok, ^path} = Local.store(path, @test_content, base_dir: base_dir)
      assert File.exists?(Path.join(base_dir, path))
    end

    test "rejects path traversal attempts", %{base_dir: base_dir} do
      assert {:error, :invalid_path} =
               Local.store("../escape.jpg", @test_content, base_dir: base_dir)

      assert {:error, :invalid_path} =
               Local.store("foo/../../escape.jpg", @test_content, base_dir: base_dir)

      assert {:error, :invalid_path} =
               Local.store("/absolute/path.jpg", @test_content, base_dir: base_dir)
    end
  end

  describe "Local.get/2" do
    test "retrieves stored file content", %{base_dir: base_dir} do
      path = "project1/item1.jpg"
      Local.store(path, @test_content, base_dir: base_dir)

      assert {:ok, @test_content} = Local.get(path, base_dir: base_dir)
    end

    test "returns {:error, :not_found} for missing file", %{base_dir: base_dir} do
      assert {:error, :not_found} = Local.get("nonexistent.jpg", base_dir: base_dir)
    end

    test "rejects path traversal attempts", %{base_dir: base_dir} do
      assert {:error, :invalid_path} = Local.get("../escape.jpg", base_dir: base_dir)
    end
  end

  describe "Local.delete/2" do
    test "deletes an existing file", %{base_dir: base_dir} do
      path = "project1/item1.jpg"
      Local.store(path, @test_content, base_dir: base_dir)

      assert :ok = Local.delete(path, base_dir: base_dir)
      refute File.exists?(Path.join(base_dir, path))
    end

    test "returns :ok for missing file", %{base_dir: base_dir} do
      assert :ok = Local.delete("nonexistent.jpg", base_dir: base_dir)
    end

    test "rejects path traversal attempts", %{base_dir: base_dir} do
      assert {:error, :invalid_path} = Local.delete("../escape.jpg", base_dir: base_dir)
    end
  end

  describe "Storage.url/1" do
    test "returns proxy URL for relative path" do
      assert Storage.url("project1/item1.jpg") == "/media/project1/item1.jpg"
    end

    test "returns proxy URL with variant path" do
      assert Storage.url("project1/item1_thumb.jpg") == "/media/project1/item1_thumb.jpg"
    end
  end

  describe "Storage.generate_path/3 and /4" do
    test "generates path without variant" do
      path = Storage.generate_path("proj-uuid", "item-uuid", "photo.jpg")
      assert path == "proj-uuid/item-uuid.jpg"
    end

    test "generates path with variant" do
      path = Storage.generate_path("proj-uuid", "item-uuid", "photo.jpg", "thumb")
      assert path == "proj-uuid/item-uuid_thumb.jpg"
    end

    test "preserves extension from filename" do
      assert Storage.generate_path("p", "i", "image.png") == "p/i.png"
      assert Storage.generate_path("p", "i", "image.webp") == "p/i.webp"
      assert Storage.generate_path("p", "i", "graphic.svg") == "p/i.svg"
    end

    test "generates path with variant and various extensions" do
      assert Storage.generate_path("p", "i", "img.png", "large") == "p/i_large.png"
      assert Storage.generate_path("p", "i", "img.gif", "sm") == "p/i_sm.gif"
    end
  end

  describe "Storage.mime_type_from_path/1" do
    test "detects jpg" do
      assert Storage.mime_type_from_path("photo.jpg") == "image/jpeg"
    end

    test "detects jpeg" do
      assert Storage.mime_type_from_path("photo.jpeg") == "image/jpeg"
    end

    test "detects png" do
      assert Storage.mime_type_from_path("image.png") == "image/png"
    end

    test "detects gif" do
      assert Storage.mime_type_from_path("animation.gif") == "image/gif"
    end

    test "detects webp" do
      assert Storage.mime_type_from_path("modern.webp") == "image/webp"
    end

    test "detects svg" do
      assert Storage.mime_type_from_path("icon.svg") == "image/svg+xml"
    end

    test "returns nil for unknown extension" do
      assert Storage.mime_type_from_path("file.xyz") == nil
    end

    test "handles paths with directories" do
      assert Storage.mime_type_from_path("project/item/photo.jpg") == "image/jpeg"
    end

    test "handles uppercase extensions" do
      assert Storage.mime_type_from_path("photo.JPG") == "image/jpeg"
      assert Storage.mime_type_from_path("image.PNG") == "image/png"
    end
  end

  describe "Storage.backend/0" do
    test "returns default backend" do
      assert Storage.backend() == :local
    end
  end
end
