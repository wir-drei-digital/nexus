defmodule Nexus.AI.Helpers do
  @moduledoc false

  alias Nexus.AI.ProseMirror

  @model "openrouter:anthropic/claude-haiku-4.5"

  def generate_seo_impl(title, content) do
    text_content = ProseMirror.extract_text(content)

    prompt_messages =
      ReqLLM.Context.new([
        ReqLLM.Context.system(
          "You are an SEO expert. Generate meta description and keywords based on page content."
        ),
        ReqLLM.Context.user("""
        Page Title: #{title}

        Page Content:
        #{text_content}

        Generate a compelling meta description (under 160 characters) and 3-5 relevant keywords.
        """)
      ])

    schema = [
      meta_description: [type: :string, required: true],
      meta_keywords: [type: {:list, :string}, required: true]
    ]

    case ReqLLM.generate_object(@model, prompt_messages, schema) do
      {:ok, response} ->
        {:ok, ReqLLM.Response.object(response)}

      {:error, reason} ->
        {:error, "Failed to generate SEO: #{inspect(reason)}"}
    end
  end

  def refine_content_impl(content, instructions, context, field_label) do
    text_content = ProseMirror.extract_text(content)

    system_prompt = """
    You are a professional content editor. You will receive the content of a specific \
    field to refine, along with the full page context for reference. Follow the user's \
    instructions precisely. Use markdown formatting with proper structure, headings, lists, \
    and emphasis as appropriate. Return ONLY the refined markdown for the target field, \
    no explanations or preamble.\
    """

    user_prompt =
      if context != "" do
        """
        ## Full Page Context
        #{context}

        ## Target Field: #{field_label}
        #{text_content}

        ## Instructions
        #{instructions}
        """
      else
        """
        ## Target Field: #{field_label}
        #{text_content}

        ## Instructions
        #{instructions}
        """
      end

    prompt_messages =
      ReqLLM.Context.new([
        ReqLLM.Context.system(system_prompt),
        ReqLLM.Context.user(user_prompt)
      ])

    case ReqLLM.generate_text(@model, prompt_messages, temperature: 0.7, max_tokens: 2000) do
      {:ok, response} ->
        {:ok, ReqLLM.Response.text(response)}

      {:error, reason} ->
        {:error, "Failed to refine content: #{inspect(reason)}"}
    end
  end
end
