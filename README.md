# Nexus

To start your Phoenix server:

* Run `mix setup` to install and setup dependencies
* Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

Ready to run in production? Please [check our deployment guides](https://hexdocs.pm/phoenix/deployment.html).

## Production Administration

When running in production without Mix installed, you can use the following scripts from the release bin directory:

### Adding Users

To add a new user via SSH on the production server:

```bash
./add_user daniel@example.com "xxx"
```

This works because the release includes the `Nexus.Release.add_user/2` function that can be executed without Mix.

## Learn more

* Official website: https://www.phoenixframework.org/
* Guides: https://hexdocs.pm/phoenix/overview.html
* Docs: https://hexdocs.pm/phoenix
* Forum: https://elixirforum.com/c/phoenix-forum
* Source: https://github.com/phoenixframework/phoenix
