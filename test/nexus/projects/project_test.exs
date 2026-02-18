defmodule Nexus.Projects.ProjectTest do
  use Nexus.DataCase, async: true

  import Nexus.Fixtures

  describe "create" do
    test "creates a project and auto-creates admin membership" do
      user = create_user()
      project = create_project(user, %{name: "My CMS", slug: "my-cms"})

      assert project.name == "My CMS"
      assert to_string(project.slug) == "my-cms"
      assert project.default_locale == "en"
      assert project.is_public == false

      memberships = Nexus.Projects.Membership.for_project!(project.id, authorize?: false)
      assert length(memberships) == 1

      membership = hd(memberships)
      assert membership.user_id == user.id
      assert membership.role == :admin
    end

    test "requires authentication" do
      assert_raise Ash.Error.Forbidden, fn ->
        Nexus.Projects.Project.create!(%{name: "Test", slug: "test"})
      end
    end

    test "enforces unique slugs" do
      user = create_user()
      create_project(user, %{slug: "unique-slug"})

      assert_raise Ash.Error.Invalid, fn ->
        create_project(user, %{slug: "unique-slug"})
      end
    end
  end

  describe "read" do
    test "members can read their projects" do
      user = create_user()
      project = create_project(user)

      result = Nexus.Projects.Project.get_by_slug!(to_string(project.slug), actor: user)
      assert result.id == project.id
    end

    test "non-members cannot read private projects" do
      user = create_user()
      other = create_user()
      project = create_project(user)

      assert_raise Ash.Error.Invalid, fn ->
        Nexus.Projects.Project.get_by_slug!(to_string(project.slug), actor: other)
      end
    end

    test "anyone can read public projects" do
      user = create_user()
      other = create_user()
      project = create_project(user, %{is_public: true})

      result = Nexus.Projects.Project.get_by_slug!(to_string(project.slug), actor: other)
      assert result.id == project.id
    end
  end

  describe "update" do
    test "admins can update projects" do
      user = create_user()
      project = create_project(user)

      updated =
        Ash.update!(project, %{name: "Updated Name"}, action: :update, actor: user)

      assert updated.name == "Updated Name"
    end

    test "non-admins cannot update projects" do
      user = create_user()
      viewer = create_user()
      project = create_project(user)

      Nexus.Projects.Membership.create!(
        %{project_id: project.id, user_id: viewer.id, role: :viewer},
        authorize?: false
      )

      assert_raise Ash.Error.Forbidden, fn ->
        Ash.update!(project, %{name: "Hacked"}, action: :update, actor: viewer)
      end
    end
  end
end
