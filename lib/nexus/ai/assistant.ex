defmodule Nexus.AI.Assistant do
  @moduledoc """
  An Ash resource for AI-powered content assistance.

  Provides generic actions for SEO generation and content refinement using LLMs.
  """

  use Ash.Resource,
    otp_app: :nexus,
    domain: Nexus.AI,
    data_layer: :embedded,
    authorizers: [Ash.Policy.Authorizer]

  code_interface do
    define :generate_seo, args: [:title, :content]
    define :refine_content, args: [:content, :instructions, :context, :field_label]
  end

  actions do
    action :generate_seo do
      argument :title, :string, allow_nil?: false
      argument :content, :string, allow_nil?: false
      returns :map

      run fn input, _context ->
        Nexus.AI.Helpers.generate_seo_impl(input.arguments.title, input.arguments.content)
      end
    end

    action :refine_content do
      argument :content, :string, allow_nil?: false
      argument :instructions, :string, allow_nil?: false
      argument :context, :string, default: ""
      argument :field_label, :string, default: ""
      returns :string

      run fn input, _context ->
        args = input.arguments

        Nexus.AI.Helpers.refine_content_impl(
          args.content,
          args.instructions,
          args.context,
          args.field_label
        )
      end
    end
  end

  policies do
    policy action(:generate_seo) do
      authorize_if always()
    end

    policy action(:refine_content) do
      authorize_if always()
    end
  end
end
