defmodule Nexus.Projects.ProjectApiKey do
  use Ash.Resource,
    otp_app: :nexus,
    domain: Nexus.Projects,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "project_api_keys"
    repo Nexus.Repo
  end

  code_interface do
    define :create
    define :read
    define :update
    define :revoke
    define :destroy
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:name, :scopes, :expires_at, :project_id, :created_by_id]

      change fn changeset, _context ->
        raw_key = generate_key()
        hash = :crypto.hash(:sha256, raw_key)

        changeset
        |> Ash.Changeset.force_change_attribute(:key_hash, hash)
        |> Ash.Changeset.force_change_attribute(:key_prefix, String.slice(raw_key, 0, 8))
        |> Ash.Changeset.after_action(fn _changeset, record ->
          {:ok, %{record | __metadata__: Map.put(record.__metadata__, :raw_key, raw_key)}}
        end)
      end
    end

    update :update do
      primary? true
      accept [:name, :scopes, :is_active, :expires_at]
    end

    update :revoke do
      accept []
      change set_attribute(:is_active, false)
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if expr(
                     exists(
                       project.memberships,
                       user_id == ^actor(:id) and role in [:admin, :editor]
                     )
                   )
    end

    policy action_type([:create, :update, :destroy]) do
      authorize_if expr(exists(project.memberships, user_id == ^actor(:id) and role == :admin))
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      public? true
    end

    attribute :key_hash, :binary do
      allow_nil? false
      sensitive? true
      public? false
    end

    attribute :key_prefix, :string do
      allow_nil? false
      public? true
    end

    attribute :scopes, {:array, Nexus.Projects.Types.ApiKeyScope} do
      allow_nil? false
      default [:pages_read]
      public? true
    end

    attribute :is_active, :boolean do
      default true
      allow_nil? false
      public? true
    end

    attribute :expires_at, :utc_datetime do
      public? true
    end

    attribute :last_used_at, :utc_datetime do
      public? true
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :project, Nexus.Projects.Project do
      allow_nil? false
    end

    belongs_to :created_by, Nexus.Accounts.User
  end

  identities do
    identity :unique_key_hash, [:key_hash]
  end

  defp generate_key do
    "nxp_" <> Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)
  end
end
