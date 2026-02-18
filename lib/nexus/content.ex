defmodule Nexus.Content do
  use Ash.Domain,
    otp_app: :nexus

  resources do
    resource Nexus.Content.Directory
    resource Nexus.Content.Page
    resource Nexus.Content.PageVersion
    resource Nexus.Content.PageLocale
  end
end
