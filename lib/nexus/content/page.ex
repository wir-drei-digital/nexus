defmodule Nexus.Content.Page do
  use Ash.Resource,
    otp_app: :nexus,
    domain: Nexus.Content,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshJsonApi.Resource],
    primary_read_warning?: false

  postgres do
    table "pages"
    repo Nexus.Repo
  end

  json_api do
    type "pages"

    routes do
      base "/projects/:project_slug/pages"
      index :list_for_project_slug, primary?: true

      route :get, "/published", :get_published_content do
        query_params [:path, :locale]
      end
    end
  end

  code_interface do
    define :create
    define :read
    define :get_by_path, args: [:project_id, :full_path]
    define :list_for_project, args: [:project_id]
    define :list_for_project_slug, args: [:project_slug]
    define :get_published_content, args: [:project_slug, :path, :locale]
    define :update
    define :publish
    define :unpublish
    define :archive
    define :soft_delete
    define :restore
    define :destroy
  end

  actions do
    defaults [:destroy]

    read :read do
      primary? true
      filter expr(is_nil(deleted_at))
    end

    create :create do
      primary? true
      accept [:slug, :position, :project_id, :folder_id, :parent_page_id, :template_slug]

      change Nexus.Content.Changes.CalculateFullPath
      change Nexus.Content.Changes.ValidateTemplate
    end

    read :get_by_path do
      argument :project_id, :uuid, allow_nil?: false
      argument :full_path, :ci_string, allow_nil?: false
      get? true

      filter expr(
               project_id == ^arg(:project_id) and full_path == ^arg(:full_path) and
                 is_nil(deleted_at)
             )
    end

    read :list_for_project do
      argument :project_id, :uuid, allow_nil?: false
      filter expr(project_id == ^arg(:project_id) and is_nil(deleted_at))
    end

    read :list_for_project_slug do
      argument :project_slug, :ci_string, allow_nil?: false

      prepare build(load: [project: []])

      filter expr(project.slug == ^arg(:project_slug) and is_nil(deleted_at))
    end

    action :get_published_content do
      argument :project_slug, :ci_string, allow_nil?: false
      argument :path, :string, allow_nil?: false
      argument :locale, :string, allow_nil?: false

      returns :map

      run Nexus.Content.Actions.GetPublishedContent
    end

    update :update do
      primary? true
      accept [:slug, :position, :folder_id, :parent_page_id, :template_slug]
      require_atomic? false

      change Nexus.Content.Changes.CalculateFullPath
    end

    update :publish do
      accept []
      require_atomic? false

      change set_attribute(:status, :published)
      change set_attribute(:published_at, &DateTime.utc_now/0)
    end

    update :unpublish do
      accept []

      change set_attribute(:status, :draft)
    end

    update :archive do
      accept []
      require_atomic? false

      change set_attribute(:status, :archived)
      change set_attribute(:archived_at, &DateTime.utc_now/0)
    end

    update :soft_delete do
      accept []
      require_atomic? false

      change set_attribute(:deleted_at, &DateTime.utc_now/0)
    end

    update :restore do
      accept []

      change set_attribute(:deleted_at, nil)
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if expr(exists(project.memberships, user_id == ^actor(:id)))
      authorize_if expr(project.is_public == true and status == :published)
      authorize_if expr(project_id == ^actor(:project_id))
    end

    policy action_type(:create) do
      authorize_if {Nexus.Projects.Checks.HasProjectRole, roles: [:admin, :editor]}
    end

    policy action([:update, :publish, :unpublish, :archive, :soft_delete, :restore]) do
      authorize_if expr(
                     exists(
                       project.memberships,
                       user_id == ^actor(:id) and role in [:admin, :editor]
                     )
                   )
    end

    policy action_type(:destroy) do
      authorize_if expr(exists(project.memberships, user_id == ^actor(:id) and role == :admin))
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :slug, :ci_string do
      allow_nil? false
      public? true
    end

    attribute :full_path, :ci_string do
      allow_nil? false
      public? true
      writable? false
    end

    attribute :status, :atom do
      constraints one_of: [:draft, :published, :archived]
      default :draft
      allow_nil? false
      public? true
    end

    attribute :template_slug, :string do
      default "default"
      allow_nil? false
      public? true
    end

    attribute :position, :integer do
      default 0
      allow_nil? false
      public? true
    end

    attribute :published_at, :utc_datetime
    attribute :archived_at, :utc_datetime
    attribute :deleted_at, :utc_datetime

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :project, Nexus.Projects.Project do
      allow_nil? false
    end

    belongs_to :folder, Nexus.Content.Folder
    belongs_to :parent_page, Nexus.Content.Page

    has_many :sub_pages, Nexus.Content.Page do
      destination_attribute :parent_page_id
    end

    has_many :page_versions, Nexus.Content.PageVersion
    has_many :page_locales, Nexus.Content.PageLocale
  end

  identities do
    identity :unique_path_per_project, [:full_path, :project_id]
  end
end
