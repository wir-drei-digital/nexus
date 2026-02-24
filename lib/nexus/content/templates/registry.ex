defmodule Nexus.Content.Templates.Registry do
  @moduledoc """
  Registry of all available page templates.
  """

  alias Nexus.Content.Templates.{Column, Field, Group, Template}

  @templates %{
    "default" => %Template{
      slug: "default",
      label: "Default",
      description: "A standard page with one rich text body.",
      fields: [
        %Field{key: :body, type: :rich_text, label: "Body", ai_refine: true}
      ]
    },
    "blog_post" => %Template{
      slug: "blog_post",
      label: "Blog Post",
      description: "A blog post with hero image, body, author, and featured toggle.",
      fields: [
        %Field{key: :hero_image, type: :image, label: "Hero Image"},
        %Field{key: :body, type: :rich_text, label: "Body", required: true, ai_refine: true},
        %Group{
          key: :metadata,
          label: "Metadata",
          columns: [
            %Column{
              fields: [
                %Field{key: :author_name, type: :text, label: "Author Name"}
              ]
            },
            %Column{
              fields: [
                %Field{key: :featured, type: :toggle, label: "Featured Post", default: false}
              ]
            }
          ]
        }
      ]
    },
    "landing_page" => %Template{
      slug: "landing_page",
      label: "Landing Page",
      description: "A structured landing page with headline, CTA, and body content.",
      fields: [
        %Field{key: :headline, type: :text, label: "Headline", required: true},
        %Field{key: :subheadline, type: :textarea, label: "Subheadline", ai_refine: true},
        %Group{
          key: :cta,
          label: "Call to Action",
          columns: [
            %Column{
              fields: [
                %Field{
                  key: :cta_text,
                  type: :text,
                  label: "CTA Button Text",
                  default: "Get Started"
                }
              ]
            },
            %Column{
              fields: [
                %Field{key: :cta_url, type: :url, label: "CTA Button URL"}
              ]
            }
          ]
        },
        %Field{key: :body, type: :rich_text, label: "Body Content", ai_refine: true}
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
