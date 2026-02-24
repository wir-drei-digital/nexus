defmodule Nexus.Content.PageVersion do
  use Ash.Resource,
    otp_app: :nexus,
    domain: Nexus.Content,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "page_versions"
    repo Nexus.Repo
  end

  code_interface do
    define :create
    define :auto_save
    define :current_for_locale, args: [:page_id, :locale]
    define :history, args: [:page_id, :locale]
    define :rollback, args: [:version_id]
  end

  actions do
    defaults [:read]

    create :create do
      primary? true

      accept [
        :locale,
        :title,
        :meta_description,
        :meta_keywords,
        :og_title,
        :og_description,
        :og_image_url,
        :template_data,
        :content_html,
        :page_id,
        :created_by_id
      ]

      change Nexus.Content.Changes.AutoIncrementVersion

      change {Ash.Resource.Change.CascadeUpdate,
              relationship: :previous_versions,
              action: :unset_current,
              copy_inputs: [],
              return_notifications?: true}
    end

    read :current_for_locale do
      argument :page_id, :uuid, allow_nil?: false
      argument :locale, :string, allow_nil?: false
      get? true

      filter expr(page_id == ^arg(:page_id) and locale == ^arg(:locale) and is_current == true)
    end

    read :history do
      argument :page_id, :uuid, allow_nil?: false
      argument :locale, :string, allow_nil?: false

      prepare build(sort: [version_number: :desc])
      filter expr(page_id == ^arg(:page_id) and locale == ^arg(:locale))
    end

    create :rollback do
      argument :version_id, :uuid, allow_nil?: false

      change fn changeset, _context ->
        version_id = Ash.Changeset.get_argument(changeset, :version_id)

        case Ash.get(Nexus.Content.PageVersion, version_id, authorize?: false) do
          {:ok, old_version} ->
            changeset
            |> Ash.Changeset.force_change_attribute(:page_id, old_version.page_id)
            |> Ash.Changeset.force_change_attribute(:locale, old_version.locale)
            |> Ash.Changeset.force_change_attribute(:title, old_version.title)
            |> Ash.Changeset.force_change_attribute(
              :meta_description,
              old_version.meta_description
            )
            |> Ash.Changeset.force_change_attribute(:meta_keywords, old_version.meta_keywords)
            |> Ash.Changeset.force_change_attribute(:og_title, old_version.og_title)
            |> Ash.Changeset.force_change_attribute(:og_description, old_version.og_description)
            |> Ash.Changeset.force_change_attribute(:og_image_url, old_version.og_image_url)
            |> Ash.Changeset.force_change_attribute(:template_data, old_version.template_data)
            |> Ash.Changeset.force_change_attribute(:content_html, old_version.content_html)

          {:error, _} ->
            Ash.Changeset.add_error(changeset,
              field: :version_id,
              message: "version not found"
            )
        end
      end

      change Nexus.Content.Changes.AutoIncrementVersion
    end

    update :auto_save do
      accept [:template_data, :content_html, :title, :meta_description, :meta_keywords]
    end

    update :unset_current do
      accept []
      change set_attribute(:is_current, false)
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if expr(exists(page.project.memberships, user_id == ^actor(:id)))
      authorize_if expr(page.project.is_public == true and page.status == :published)
      authorize_if expr(page.project_id == ^actor(:project_id))
    end

    policy action_type(:create) do
      authorize_if {Nexus.Content.Checks.HasContentRole, roles: [:admin, :editor]}
    end

    policy action(:auto_save) do
      authorize_if {Nexus.Content.Checks.HasContentRole, roles: [:admin, :editor]}
    end

    policy action(:unset_current) do
      authorize_if always()
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :version_number, :integer do
      allow_nil? false
      public? true
      writable? false
    end

    attribute :locale, :string do
      allow_nil? false
      public? true
      default "en"
    end

    attribute :title, :string do
      public? true
    end

    attribute :meta_description, :string do
      public? true
    end

    attribute :meta_keywords, {:array, :string} do
      public? true
      default []
    end

    attribute :og_title, :string do
      public? true
    end

    attribute :og_description, :string do
      public? true
    end

    attribute :og_image_url, :string do
      public? true
    end

    attribute :template_data, :map do
      public? true
      default %{"body" => %{"type" => "doc", "content" => [%{"type" => "paragraph"}]}}
    end

    attribute :content_html, :string do
      public? true
    end

    attribute :is_current, :boolean do
      default false
      allow_nil? false
      public? true
    end

    create_timestamp :inserted_at
  end

  relationships do
    belongs_to :page, Nexus.Content.Page do
      allow_nil? false
    end

    belongs_to :created_by, Nexus.Accounts.User

    has_many :previous_versions, Nexus.Content.PageVersion do
      filter expr(
               page_id == parent(page_id) and locale == parent(locale) and is_current == true and
                 id != parent(id)
             )

      no_attributes? true
    end
  end

  calculations do
    calculate :rendered_html, :string do
      calculation Nexus.Content.Calculations.RenderedHtml
      public? true
    end
  end

  identities do
    identity :unique_version, [:page_id, :locale, :version_number]
  end
end
