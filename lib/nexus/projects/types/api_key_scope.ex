defmodule Nexus.Projects.Types.ApiKeyScope do
  use Ash.Type.Enum,
    values: [
      :pages_read,
      :pages_write,
      :pages_update,
      :pages_delete,
      :pages_publish,
      :directories_read,
      :directories_write,
      :full_access
    ]
end
