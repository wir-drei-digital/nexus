defmodule NexusWeb.Presence do
  use Phoenix.Presence,
    otp_app: :nexus,
    pubsub_server: Nexus.PubSub
end
