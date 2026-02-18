defmodule Nexus.Projects.Project do
  use Ash.Resource,
    otp_app: :nexus,
    domain: Nexus.Projects,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "projects"
    repo Nexus.Repo
  end

  code_interface do
    define :create
    define :read
    define :get_by_slug, args: [:slug]
    define :update
    define :destroy
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:name, :slug, :description, :is_public, :default_locale]

      change Nexus.Projects.Changes.CreateOwnerMembership
    end

    read :get_by_slug do
      get_by :slug
    end

    update :update do
      primary? true
      accept [:name, :description, :is_public, :default_locale]
    end
  end

  policies do
    policy action_type(:create) do
      description "Any authenticated user can create a project"
      authorize_if actor_present()
    end

    policy action_type(:read) do
      description "Members can read their projects; public projects are visible to all"
      authorize_if expr(is_public == true)
      authorize_if expr(exists(memberships, user_id == ^actor(:id)))
    end

    policy action_type(:update) do
      description "Only admins can update projects"
      authorize_if expr(exists(memberships, user_id == ^actor(:id) and role == :admin))
    end

    policy action_type(:destroy) do
      description "Only admins can destroy projects"
      authorize_if expr(exists(memberships, user_id == ^actor(:id) and role == :admin))
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      public? true
    end

    attribute :slug, :ci_string do
      allow_nil? false
      public? true
    end

    attribute :description, :string do
      public? true
    end

    attribute :is_public, :boolean do
      default false
      allow_nil? false
      public? true
    end

    attribute :default_locale, :string do
      default "en"
      allow_nil? false
      public? true
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    has_many :memberships, Nexus.Projects.Membership
    has_many :directories, Nexus.Content.Directory
    has_many :pages, Nexus.Content.Page
  end

  aggregates do
    count :page_count, :pages do
      filter expr(is_nil(deleted_at))
    end

    count :directory_count, :directories
  end

  identities do
    identity :unique_slug, [:slug]
  end
end
