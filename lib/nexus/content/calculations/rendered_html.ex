defmodule Nexus.Content.Calculations.RenderedHtml do
  @moduledoc """
  Calculation that renders template_data into HTML using the template renderer.
  """

  require Ash.Query

  alias Nexus.Content.Templates.Renderer

  def init(opts), do: {:ok, opts}

  def calculate(records, _opts, _context) do
    Enum.map(records, fn record ->
      # The :page relationship should be loaded by the `load/3` callback
      case record.page do
        nil -> nil
        page -> Renderer.render(page.template_slug, record.template_data)
      end
    end)
  end

  def load(_query, _opts, _context) do
    [:page]
  end
end
