defmodule Nexus.Fixtures do
  @moduledoc """
  Test fixtures for creating common resources.
  """

  def unique_email, do: "user_#{System.unique_integer([:positive])}@example.com"
  def unique_slug, do: "slug-#{System.unique_integer([:positive])}"

  def create_user(attrs \\ %{}) do
    email = Map.get(attrs, :email, unique_email())

    Nexus.Accounts.User
    |> Ash.Changeset.for_create(:register_with_password, %{
      email: email,
      password: "Password123!",
      password_confirmation: "Password123!"
    })
    |> Ash.create!(authorize?: false)
  end

  def create_project(user, attrs \\ %{}) do
    params =
      Map.merge(
        %{name: "Test Project", slug: unique_slug()},
        attrs
      )

    Nexus.Projects.Project.create!(params, actor: user)
  end

  def create_folder(project, user, attrs \\ %{}) do
    params =
      Map.merge(
        %{name: "Test Dir", slug: unique_slug(), project_id: project.id},
        attrs
      )

    Nexus.Content.Folder.create!(params, actor: user)
  end

  def create_page(project, user, attrs \\ %{}) do
    params =
      Map.merge(
        %{slug: unique_slug(), project_id: project.id},
        attrs
      )

    Nexus.Content.Page.create!(params, actor: user)
  end

  def create_page_version(page, user, attrs \\ %{}) do
    params =
      Map.merge(
        %{
          page_id: page.id,
          locale: "en",
          title: "Test Page",
          template_data: %{"body" => %{"type" => "doc", "content" => []}},
          created_by_id: user.id
        },
        attrs
      )

    Nexus.Content.PageVersion.create!(params, actor: user)
  end

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
end
