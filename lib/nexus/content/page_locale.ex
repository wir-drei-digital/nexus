defmodule Nexus.Content.PageLocale do
  use Ash.Resource,
    otp_app: :nexus,
    domain: Nexus.Content,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "page_locales"
    repo Nexus.Repo
  end

  code_interface do
    define :create
    define :read
    define :for_page, args: [:page_id]
    define :publish_locale
    define :mark_changed
    define :unpublish_locale
    define :destroy
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:locale, :page_id, :published_version_id]
    end

    read :for_page do
      argument :page_id, :uuid, allow_nil?: false
      filter expr(page_id == ^arg(:page_id))
    end

    update :publish_locale do
      accept [:published_version_id]
      change set_attribute(:has_unpublished_changes, false)
    end

    update :mark_changed do
      accept []
      change set_attribute(:has_unpublished_changes, true)
    end

    update :unpublish_locale do
      accept []
      change set_attribute(:published_version_id, nil)
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if expr(exists(page.project.memberships, user_id == ^actor(:id)))
      authorize_if expr(page.project.is_public == true)
      authorize_if expr(page.project_id == ^actor(:project_id))
    end

    policy action_type(:create) do
      authorize_if {Nexus.Content.Checks.HasContentRole, roles: [:admin, :editor]}
    end

    policy action_type([:update, :destroy]) do
      authorize_if expr(
                     exists(
                       page.project.memberships,
                       user_id == ^actor(:id) and role in [:admin, :editor]
                     )
                   )
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :locale, :string do
      allow_nil? false
      public? true
    end

    attribute :has_unpublished_changes, :boolean do
      default false
      allow_nil? false
      public? true
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :page, Nexus.Content.Page do
      allow_nil? false
    end

    belongs_to :published_version, Nexus.Content.PageVersion
  end

  identities do
    identity :unique_locale_per_page, [:page_id, :locale]
  end
end
