defmodule Nexus.Projects.Membership do
  use Ash.Resource,
    otp_app: :nexus,
    domain: Nexus.Projects,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "memberships"
    repo Nexus.Repo
  end

  code_interface do
    define :create
    define :read
    define :for_project, args: [:project_id]
    define :update_role
    define :destroy
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:role, :project_id, :user_id]
    end

    read :for_project do
      argument :project_id, :uuid, allow_nil?: false
      filter expr(project_id == ^arg(:project_id))
    end

    update :update_role do
      accept [:role]
    end
  end

  policies do
    policy action_type(:read) do
      description "Members can see other members of their projects"
      authorize_if expr(exists(project.memberships, user_id == ^actor(:id)))
    end

    policy action_type(:create) do
      description "Only project admins can add members"
      authorize_if expr(exists(project.memberships, user_id == ^actor(:id) and role == :admin))
    end

    policy action_type(:update) do
      description "Only project admins can update member roles"
      authorize_if expr(exists(project.memberships, user_id == ^actor(:id) and role == :admin))
    end

    policy action_type(:destroy) do
      description "Only project admins can remove members"
      authorize_if expr(exists(project.memberships, user_id == ^actor(:id) and role == :admin))
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :role, :atom do
      allow_nil? false
      public? true
      constraints one_of: [:admin, :editor, :viewer]
      default :viewer
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :project, Nexus.Projects.Project do
      allow_nil? false
    end

    belongs_to :user, Nexus.Accounts.User do
      allow_nil? false
    end
  end

  identities do
    identity :unique_user_project, [:user_id, :project_id]
  end
end
