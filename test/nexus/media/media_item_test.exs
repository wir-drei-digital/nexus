defmodule Nexus.Media.MediaItemTest do
  use Nexus.DataCase, async: true

  import Nexus.Fixtures

  setup do
    user = create_user()
    project = create_project(user)
    %{user: user, project: project}
  end

  describe "create" do
    test "creates a media item with pending status", %{user: user, project: project} do
      item = create_media_item(project, user)

      assert item.filename =~ "test-"
      assert item.mime_type == "image/jpeg"
      assert item.file_size == 1024
      assert item.storage_backend == "local"
      assert item.status == :pending
      assert item.project_id == project.id
      assert item.uploaded_by_id == user.id
      assert item.variants == %{}
      assert is_nil(item.width)
      assert is_nil(item.height)
      assert is_nil(item.alt_text)
    end
  end

  describe "list_for_project" do
    test "returns items for a project", %{user: user, project: project} do
      item1 = create_media_item(project, user)
      item2 = create_media_item(project, user)

      items = Nexus.Media.MediaItem.list_for_project!(project.id, actor: user)

      ids = Enum.map(items, & &1.id)
      assert item1.id in ids
      assert item2.id in ids
    end

    test "does not return items from other projects", %{user: user, project: project} do
      create_media_item(project, user)

      other_project = create_project(user)
      create_media_item(other_project, user)

      items = Nexus.Media.MediaItem.list_for_project!(project.id, actor: user)
      assert length(items) == 1
      assert hd(items).project_id == project.id
    end
  end

  describe "update_alt_text" do
    test "updates alt text", %{user: user, project: project} do
      item = create_media_item(project, user)

      updated = Nexus.Media.MediaItem.update_alt_text!(item, %{alt_text: "A sunset"}, actor: user)

      assert updated.alt_text == "A sunset"
    end
  end

  describe "update_status" do
    test "sets status to ready with variants and dimensions", %{user: user, project: project} do
      item = create_media_item(project, user)

      variants = %{"thumb" => "#{project.id}/thumb.jpg", "medium" => "#{project.id}/medium.jpg"}

      updated =
        Nexus.Media.MediaItem.update_status!(item, %{
          status: :ready,
          width: 1920,
          height: 1080,
          variants: variants
        })

      assert updated.status == :ready
      assert updated.width == 1920
      assert updated.height == 1080
      assert updated.variants == variants
    end
  end

  describe "destroy" do
    test "deletes a media item", %{user: user, project: project} do
      item = create_media_item(project, user)

      assert :ok = Nexus.Media.MediaItem.destroy(item, actor: user)

      items = Nexus.Media.MediaItem.list_for_project!(project.id, actor: user)
      assert Enum.empty?(items)
    end
  end
end
