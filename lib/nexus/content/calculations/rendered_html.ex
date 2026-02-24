defmodule Nexus.Content.Calculations.RenderedHtml do
  @moduledoc """
  Calculation that renders template_data into HTML using the template renderer.
  """

  use Ash.Resource.Calculation

  alias Nexus.Content.Templates.Renderer

  @impl true
  def calculate(records, _opts, _context) do
    Enum.map(records, fn record ->
      case record.page do
        nil -> nil
        page -> Renderer.render(page.template_slug, record.template_data)
      end
    end)
  end

  @impl true
  def load(_query, _opts, _context) do
    [:page]
  end
end
