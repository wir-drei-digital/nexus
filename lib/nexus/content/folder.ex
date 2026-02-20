defmodule Nexus.Content.Folder do
  use Ash.Resource,
    otp_app: :nexus,
    domain: Nexus.Content,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshJsonApi.Resource]

  postgres do
    table "folders"
    repo Nexus.Repo
  end

  json_api do
    type "folders"

    routes do
      base "/projects/:project_slug/folders"
      index :for_project_slug, primary?: true
    end
  end

  code_interface do
    define :create
    define :read
    define :for_project, args: [:project_id]
    define :for_project_slug, args: [:project_slug]
    define :get_by_path, args: [:project_id, :full_path]
    define :update
    define :destroy
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:name, :slug, :position, :project_id, :parent_id]

      change Nexus.Content.Changes.CalculateFullPath
    end

    read :for_project do
      argument :project_id, :uuid, allow_nil?: false
      filter expr(project_id == ^arg(:project_id))
    end

    read :for_project_slug do
      argument :project_slug, :ci_string, allow_nil?: false

      prepare build(load: [project: []])

      filter expr(project.slug == ^arg(:project_slug))
    end

    read :get_by_path do
      argument :project_id, :uuid, allow_nil?: false
      argument :full_path, :ci_string, allow_nil?: false
      get? true

      filter expr(project_id == ^arg(:project_id) and full_path == ^arg(:full_path))
    end

    update :update do
      primary? true
      accept [:name, :slug, :position, :parent_id]
      require_atomic? false

      change Nexus.Content.Changes.CalculateFullPath
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if expr(exists(project.memberships, user_id == ^actor(:id)))
      authorize_if expr(project.is_public == true)
      authorize_if expr(project_id == ^actor(:project_id))
    end

    policy action_type(:create) do
      authorize_if {Nexus.Projects.Checks.HasProjectRole, roles: [:admin, :editor]}
    end

    policy action_type([:update, :destroy]) do
      authorize_if expr(
                     exists(
                       project.memberships,
                       user_id == ^actor(:id) and role in [:admin, :editor]
                     )
                   )
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

    attribute :full_path, :ci_string do
      allow_nil? false
      public? true
      writable? false
    end

    attribute :position, :integer do
      default 0
      allow_nil? false
      public? true
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :project, Nexus.Projects.Project do
      allow_nil? false
    end

    belongs_to :parent, Nexus.Content.Folder

    has_many :children, Nexus.Content.Folder do
      destination_attribute :parent_id
    end

    has_many :pages, Nexus.Content.Page
  end

  identities do
    identity :unique_path_per_project, [:full_path, :project_id]
  end
end
