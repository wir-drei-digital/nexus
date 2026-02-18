defmodule Nexus.Content.Templates.Registry do
  @moduledoc """
  Registry of all available page templates.
  """

  alias Nexus.Content.Templates.{Section, Template}

  @templates %{
    "default" => %Template{
      slug: "default",
      label: "Default",
      description: "A standard page with one rich text body.",
      sections: [
        %Section{key: :body, type: :rich_text, label: "Body"}
      ]
    },
    "blog_post" => %Template{
      slug: "blog_post",
      label: "Blog Post",
      description: "A blog post with hero image, body, author, and featured toggle.",
      sections: [
        %Section{key: :hero_image, type: :image, label: "Hero Image"},
        %Section{key: :body, type: :rich_text, label: "Body", required: true},
        %Section{key: :author_name, type: :text, label: "Author Name"},
        %Section{key: :featured, type: :toggle, label: "Featured Post", default: false}
      ]
    },
    "landing_page" => %Template{
      slug: "landing_page",
      label: "Landing Page",
      description: "A structured landing page with headline, CTA, and body content.",
      sections: [
        %Section{key: :headline, type: :text, label: "Headline", required: true},
        %Section{key: :subheadline, type: :textarea, label: "Subheadline"},
        %Section{key: :cta_text, type: :text, label: "CTA Button Text", default: "Get Started"},
        %Section{key: :cta_url, type: :url, label: "CTA Button URL"},
        %Section{key: :body, type: :rich_text, label: "Body Content"}
      ]
    }
  }

  @doc "Returns all registered templates as a map of slug => Template."
  @spec all() :: %{String.t() => Template.t()}
  def all, do: @templates

  @doc "Returns the template for the given slug, or nil."
  @spec get(String.t()) :: Template.t() | nil
  def get(slug), do: Map.get(@templates, slug)

  @doc "Returns true if a template with the given slug exists."
  @spec exists?(String.t()) :: boolean()
  def exists?(slug), do: Map.has_key?(@templates, slug)

  @doc "Returns all template slugs."
  @spec slugs() :: [String.t()]
  def slugs, do: Map.keys(@templates)

  @doc "Returns templates available for a given project (filtered by available_templates)."
  @spec available_for_project([String.t()]) :: [Template.t()]
  def available_for_project(available_slugs) do
    available_slugs
    |> Enum.map(&get/1)
    |> Enum.reject(&is_nil/1)
  end
end
