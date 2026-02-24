defmodule Nexus.Release do
  @moduledoc """
  Used for executing DB release tasks when run in production without Mix
  installed.
  """
  @app :nexus

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  def add_user(email, password) do
    start_app()

    Nexus.Accounts.User
    |> Ash.Changeset.for_create(:register_with_password, %{
      email: email,
      password: password,
      password_confirmation: password
    })
    |> Ash.Changeset.force_change_attribute(:confirmed_at, DateTime.utc_now())
    |> Ash.create!(authorize?: false)

    IO.puts("✓ User created and confirmed: #{email}")
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp start_app do
    load_app()
    Application.ensure_all_started(@app)
  end

  defp load_app do
    # Many platforms require SSL when connecting to the database
    Application.ensure_all_started(:ssl)
    Application.ensure_loaded(@app)
  end
end
