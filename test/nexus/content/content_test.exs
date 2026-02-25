defmodule Nexus.Content.ContentTest do
  use Nexus.DataCase, async: true

  import Nexus.Fixtures

  setup do
    user = create_user()
    project = create_project(user)
    %{user: user, project: project}
  end

  describe "folders" do
    test "creates a folder with full_path", %{user: user, project: project} do
      folder = create_folder(project, user, %{name: "Blog", slug: "blog"})

      assert to_string(folder.full_path) == "blog"
      assert folder.name == "Blog"
    end

    test "builds nested full_path", %{user: user, project: project} do
      parent = create_folder(project, user, %{name: "Blog", slug: "blog"})

      child =
        create_folder(project, user, %{
          name: "2024",
          slug: "2024",
          parent_id: parent.id
        })

      assert to_string(child.full_path) == "blog/2024"
    end

    test "enforces unique path per project", %{user: user, project: project} do
      create_folder(project, user, %{name: "Blog", slug: "blog"})

      assert_raise Ash.Error.Invalid, fn ->
        create_folder(project, user, %{name: "Blog 2", slug: "blog"})
      end
    end
  end

  describe "pages" do
    test "creates a page with full_path", %{user: user, project: project} do
      page = create_page(project, user, %{slug: "hello-world"})

      assert to_string(page.full_path) == "hello-world"
    end

    test "builds full_path from folder", %{user: user, project: project} do
      folder = create_folder(project, user, %{name: "Blog", slug: "blog"})

      page =
        create_page(project, user, %{slug: "my-post", folder_id: folder.id})

      assert to_string(page.full_path) == "blog/my-post"
    end

    test "soft delete excludes from listing", %{user: user, project: project} do
      page = create_page(project, user)

      deleted = Nexus.Content.Page.soft_delete!(page, actor: user)
      assert deleted.deleted_at != nil

      # Soft-deleted pages are excluded from default read
      pages = Nexus.Content.Page.list_for_project!(project.id, actor: user)
      assert Enum.all?(pages, fn p -> p.id != page.id end)
    end

    test "archive sets archived_at", %{user: user, project: project} do
      page = create_page(project, user)

      archived = Nexus.Content.Page.archive!(page, actor: user)
      assert archived.archived_at != nil
    end
  end

  describe "page versions" do
    test "auto-increments version numbers", %{user: user, project: project} do
      page = create_page(project, user)

      v1 = create_page_version(page, user, %{title: "First"})
      assert v1.version_number == 1
      assert v1.is_current == true

      v2 = create_page_version(page, user, %{title: "Second"})
      assert v2.version_number == 2
      assert v2.is_current == true

      # v1 should no longer be current
      v1_reloaded = Ash.get!(Nexus.Content.PageVersion, v1.id, authorize?: false)
      assert v1_reloaded.is_current == false
    end

    test "separate version sequences per locale", %{user: user, project: project} do
      page = create_page(project, user)

      en_v1 = create_page_version(page, user, %{locale: "en", title: "English"})
      fr_v1 = create_page_version(page, user, %{locale: "fr", title: "French"})

      assert en_v1.version_number == 1
      assert fr_v1.version_number == 1
    end

    test "current_for_locale returns the latest version", %{user: user, project: project} do
      page = create_page(project, user)

      create_page_version(page, user, %{title: "Old"})
      create_page_version(page, user, %{title: "New"})

      current = Nexus.Content.PageVersion.current_for_locale!(page.id, "en", authorize?: false)
      assert current.title == "New"
      assert current.version_number == 2
    end

    test "history returns versions in descending order", %{user: user, project: project} do
      page = create_page(project, user)

      create_page_version(page, user, %{title: "V1"})
      create_page_version(page, user, %{title: "V2"})
      create_page_version(page, user, %{title: "V3"})

      history = Nexus.Content.PageVersion.history!(page.id, "en", authorize?: false)
      assert length(history) == 3
      assert hd(history).version_number == 3
    end
  end

  describe "page locales" do
    test "creates locale and publishes version", %{user: user, project: project} do
      page = create_page(project, user)
      version = create_page_version(page, user)

      page_locale =
        Nexus.Content.PageLocale.create!(
          %{page_id: page.id, locale: "en"},
          actor: user
        )

      updated =
        Ash.update!(page_locale, %{published_version_id: version.id},
          action: :publish_locale,
          actor: user
        )

      assert updated.published_version_id == version.id
    end
  end
end
