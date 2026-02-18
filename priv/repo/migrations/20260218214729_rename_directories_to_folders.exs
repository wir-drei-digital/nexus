defmodule Nexus.Repo.Migrations.RenameDirectoriesToFolders do
  @moduledoc """
  Renames the directories table to folders and directory_id to folder_id.
  """

  use Ecto.Migration

  def up do
    # Drop old constraints and indexes
    drop_if_exists unique_index(:directories, [:full_path, :project_id],
                     name: "directories_unique_path_per_project_index"
                   )

    drop constraint(:pages, "pages_directory_id_fkey")
    drop constraint(:directories, "directories_parent_id_fkey")
    drop constraint(:directories, "directories_project_id_fkey")

    # Rename table
    rename table(:directories), to: table(:folders)

    # Rename column on pages
    rename table(:pages), :directory_id, to: :folder_id

    # Recreate constraints with new names
    alter table(:folders) do
      modify :project_id,
             references(:projects,
               column: :id,
               name: "folders_project_id_fkey",
               type: :uuid,
               prefix: "public"
             ),
             null: false

      modify :parent_id,
             references(:folders,
               column: :id,
               name: "folders_parent_id_fkey",
               type: :uuid,
               prefix: "public"
             )
    end

    alter table(:pages) do
      modify :folder_id,
             references(:folders,
               column: :id,
               name: "pages_folder_id_fkey",
               type: :uuid,
               prefix: "public"
             )
    end

    create unique_index(:folders, [:full_path, :project_id],
             name: "folders_unique_path_per_project_index"
           )
  end

  def down do
    drop_if_exists unique_index(:folders, [:full_path, :project_id],
                     name: "folders_unique_path_per_project_index"
                   )

    drop constraint(:pages, "pages_folder_id_fkey")
    drop constraint(:folders, "folders_parent_id_fkey")
    drop constraint(:folders, "folders_project_id_fkey")

    rename table(:folders), to: table(:directories)
    rename table(:pages), :folder_id, to: :directory_id

    alter table(:directories) do
      modify :project_id,
             references(:projects,
               column: :id,
               name: "directories_project_id_fkey",
               type: :uuid,
               prefix: "public"
             ),
             null: false

      modify :parent_id,
             references(:directories,
               column: :id,
               name: "directories_parent_id_fkey",
               type: :uuid,
               prefix: "public"
             )
    end

    alter table(:pages) do
      modify :directory_id,
             references(:directories,
               column: :id,
               name: "pages_directory_id_fkey",
               type: :uuid,
               prefix: "public"
             )
    end

    create unique_index(:directories, [:full_path, :project_id],
             name: "directories_unique_path_per_project_index"
           )
  end
end
