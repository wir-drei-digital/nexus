defmodule Nexus.Projects do
  use Ash.Domain,
    otp_app: :nexus

  resources do
    resource Nexus.Projects.Project
    resource Nexus.Projects.Membership
    resource Nexus.Projects.ProjectApiKey
  end
end
