defmodule Nexus.Content do
  use Ash.Domain,
    otp_app: :nexus,
    extensions: [AshJsonApi.Domain]

  json_api do
    prefix "/api/v1"
    log_errors? true
  end

  resources do
    resource Nexus.Content.Folder
    resource Nexus.Content.Page
    resource Nexus.Content.PageVersion
    resource Nexus.Content.PageLocale
  end
end
