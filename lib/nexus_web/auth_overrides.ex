defmodule NexusWeb.AuthOverrides do
  use AshAuthentication.Phoenix.Overrides

  alias AshAuthentication.Phoenix.Components

  # Show Nexus logo and branding instead of Ash logo
  override Components.Banner do
    set :href_url, "/admin"
    set :root_class, "w-full flex justify-center py-4 border-b border-base-200"
    set :image_url, nil
    set :dark_image_url, nil
    set :text_class, "flex items-center gap-2 text-lg font-medium"
    set :text, "⟐ NEXUS"
  end

  # Disable registration
  override Components.Password do
    set :register_toggle_text, nil
  end
end
