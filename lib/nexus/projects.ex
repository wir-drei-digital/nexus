defmodule Nexus.Projects do
  use Ash.Domain,
    otp_app: :nexus,
    extensions: [AshJsonApi.Domain]

  json_api do
    prefix "/api/v1"
    log_errors? true
  end

  resources do
    resource Nexus.Projects.Project
    resource Nexus.Projects.Membership
    resource Nexus.Projects.ProjectApiKey
  end
end
