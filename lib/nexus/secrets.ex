defmodule Nexus.Secrets do
  use AshAuthentication.Secret

  def secret_for(
        [:authentication, :tokens, :signing_secret],
        Nexus.Accounts.User,
        _opts,
        _context
      ) do
    Application.fetch_env(:nexus, :token_signing_secret)
  end
end
