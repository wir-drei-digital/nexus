defmodule Nexus.Media do
  use Ash.Domain,
    otp_app: :nexus,
    extensions: [AshJsonApi.Domain]

  json_api do
    prefix "/api/v1"
    log_errors? true
  end

  resources do
    resource Nexus.Media.MediaItem
  end
end
