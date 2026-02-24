defmodule Nexus.Media.MediaItem do
  use Ash.Resource,
    otp_app: :nexus,
    domain: Nexus.Media,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshJsonApi.Resource]

  postgres do
    table "media_items"
    repo Nexus.Repo
  end

  json_api do
    type "media_items"

    routes do
      base "/projects/:project_id/media"
      index :list_for_project, primary?: true
      get :read, route: "/:id"
      delete :destroy, route: "/:id"
    end
  end

  code_interface do
    define :create
    define :read
    define :list_for_project, args: [:project_id]
    define :update_alt_text
    define :update_status
    define :destroy
  end

  actions do
    defaults [:read]

    create :create do
      primary? true

      accept [
        :filename,
        :file_path,
        :mime_type,
        :file_size,
        :storage_backend,
        :project_id,
        :uploaded_by_id
      ]

      change set_attribute(:status, :pending)
    end

    read :list_for_project do
      argument :project_id, :uuid, allow_nil?: false

      filter expr(project_id == ^arg(:project_id))

      prepare build(sort: [inserted_at: :desc])
    end

    update :update_alt_text do
      accept [:alt_text]
    end

    update :update_status do
      accept [:status, :width, :height, :variants]
      require_atomic? false
    end

    destroy :destroy do
      primary? true
      require_atomic? false
      change Nexus.Media.Changes.DeleteFiles
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if expr(exists(project.memberships, user_id == ^actor(:id)))
      authorize_if expr(project.is_public == true)
    end

    policy action_type(:create) do
      authorize_if {Nexus.Projects.Checks.HasProjectRole, roles: [:admin, :editor]}
    end

    policy action(:update_alt_text) do
      authorize_if expr(
                     exists(
                       project.memberships,
                       user_id == ^actor(:id) and role in [:admin, :editor]
                     )
                   )
    end

    policy action(:update_status) do
      authorize_if always()
    end

    policy action_type(:destroy) do
      authorize_if expr(exists(project.memberships, user_id == ^actor(:id) and role == :admin))
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :filename, :string do
      allow_nil? false
      public? true
    end

    attribute :file_path, :string do
      allow_nil? false
      public? true
    end

    attribute :mime_type, :string do
      allow_nil? false
      public? true
    end

    attribute :file_size, :integer do
      allow_nil? false
      public? true
    end

    attribute :width, :integer do
      public? true
    end

    attribute :height, :integer do
      public? true
    end

    attribute :alt_text, :string do
      public? true
    end

    attribute :variants, :map do
      default %{}
      public? true
    end

    attribute :storage_backend, :string do
      allow_nil? false
      public? true
    end

    attribute :status, :atom do
      constraints one_of: [:pending, :processing, :ready, :error]
      default :pending
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

    belongs_to :uploaded_by, Nexus.Accounts.User do
      allow_nil? false
    end
  end
end
