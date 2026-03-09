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
    define :generate_seo, args: [:title, :content, :system_prompt]

    define :refine_content,
      args: [:content, :instructions, :context, :field_label, :system_prompt]

    define :translate_content,
      args: [:content, :source_locale, :target_locale, :field_types, :system_prompt]
  end

  actions do
    action :generate_seo do
      argument :title, :string, allow_nil?: false
      argument :content, :string, allow_nil?: false
      argument :system_prompt, :string
      returns :map

      run fn input, _context ->
        args = input.arguments

        opts =
          if args.system_prompt not in [nil, ""],
            do: [system_prompt: args.system_prompt],
            else: []

        Nexus.AI.Helpers.generate_seo_impl(args.title, args.content, opts)
      end
    end

    action :refine_content do
      argument :content, :string, allow_nil?: false
      argument :instructions, :string, allow_nil?: false
      argument :context, :string, default: ""
      argument :field_label, :string, default: ""
      argument :system_prompt, :string
      returns :string

      run fn input, _context ->
        args = input.arguments

        opts =
          if args.system_prompt not in [nil, ""],
            do: [system_prompt: args.system_prompt],
            else: []

        Nexus.AI.Helpers.refine_content_impl(
          args.content,
          args.instructions,
          args.context,
          args.field_label,
          opts
        )
      end
    end

    action :translate_content do
      argument :content, :map, allow_nil?: false
      argument :source_locale, :string, allow_nil?: false
      argument :target_locale, :string, allow_nil?: false
      argument :field_types, :map, allow_nil?: false
      argument :system_prompt, :string
      returns :map

      run fn input, _context ->
        args = input.arguments

        opts =
          if args.system_prompt not in [nil, ""],
            do: [system_prompt: args.system_prompt],
            else: []

        Nexus.AI.Helpers.translate_content_impl(
          args.content,
          args.source_locale,
          args.target_locale,
          args.field_types,
          opts
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

    policy action(:translate_content) do
      authorize_if always()
    end
  end
end
