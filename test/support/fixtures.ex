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

  def create_directory(project, user, attrs \\ %{}) do
    params =
      Map.merge(
        %{name: "Test Dir", slug: unique_slug(), project_id: project.id},
        attrs
      )

    Nexus.Content.Directory.create!(params, actor: user)
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
          blocks: [],
          created_by_id: user.id
        },
        attrs
      )

    Nexus.Content.PageVersion.create!(params, actor: user)
  end
end
