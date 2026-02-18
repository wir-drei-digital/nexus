defmodule Nexus.Accounts do
  use Ash.Domain,
    otp_app: :nexus

  resources do
    resource Nexus.Accounts.Token
    resource Nexus.Accounts.User
    resource Nexus.Accounts.ApiKey
  end
end
