defmodule Nexus.AI.Helpers do
  @moduledoc false

  alias Nexus.AI.ProseMirror

  @model "openrouter:anthropic/claude-haiku-4.5"
  @translatable_types [:text, :textarea, :rich_text]

  @doc """
  Splits a template_data map into `{translatable, direct_copy}` based on field types.

  Translatable types: `:text`, `:textarea`, `:rich_text`. Everything else is direct-copy.
  """
  def classify_fields(template_data, field_types) do
    Enum.reduce(template_data, {%{}, %{}}, fn {key, value}, {translatable, direct} ->
      type = Map.get(field_types, key)

      if type in @translatable_types do
        {Map.put(translatable, key, value), direct}
      else
        {translatable, Map.put(direct, key, value)}
      end
    end)
  end

  @doc """
  Converts rich_text ProseMirror JSON fields to markdown strings.
  Leaves text/textarea as-is.
  """
  def prepare_translation_content(translatable, field_types) do
    Map.new(translatable, fn {key, value} ->
      case Map.get(field_types, key) do
        :rich_text -> {key, ProseMirror.to_markdown(value)}
        _ -> {key, to_string(value || "")}
      end
    end)
  end

  @doc """
  Converts translated markdown strings back to ProseMirror JSON for rich_text fields.
  """
  def apply_translation_results(results, field_types) do
    Map.new(results, fn {key, value} ->
      case Map.get(field_types, key) do
        :rich_text ->
          case ProseMirror.from_markdown(to_string(value)) do
            {:ok, doc} -> {key, doc}
            {:error, _} -> {key, ProseMirror.default_doc()}
          end

        _ ->
          {key, to_string(value)}
      end
    end)
  end

  @doc """
  Translates content fields from one locale to another using an LLM.

  Prepares content (converting rich_text to markdown), calls the LLM,
  then converts results back to their original formats.
  """
  def translate_content_impl(content, source_locale, target_locale, field_types) do
    prepared = prepare_translation_content(content, field_types)

    prompt_messages =
      ReqLLM.Context.new([
        ReqLLM.Context.system("""
        You are a professional translator. Translate all content from #{locale_name(source_locale)} to #{locale_name(target_locale)}.
        Preserve all formatting, markdown structure, links, and special characters exactly.
        Do not add or remove any content — translate faithfully.
        """),
        ReqLLM.Context.user("""
        Translate each field value below. Return a JSON object with the same keys but translated values.

        #{Jason.encode!(prepared, pretty: true)}
        """)
      ])

    schema =
      Enum.map(prepared, fn {key, _} ->
        {String.to_atom(key), [type: :string, required: true]}
      end)

    case ReqLLM.generate_object(@model, prompt_messages, schema) do
      {:ok, response} ->
        translated = ReqLLM.Response.object(response)
        translated = Map.new(translated, fn {k, v} -> {to_string(k), v} end)
        {:ok, apply_translation_results(translated, field_types)}

      {:error, reason} ->
        {:error, "Translation failed: #{inspect(reason)}"}
    end
  end

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

  defp locale_name(code) do
    %{
      "en" => "English",
      "de" => "German",
      "fr" => "French",
      "es" => "Spanish",
      "it" => "Italian",
      "pt" => "Portuguese",
      "nl" => "Dutch",
      "pl" => "Polish",
      "ru" => "Russian",
      "zh" => "Chinese",
      "ja" => "Japanese",
      "ko" => "Korean",
      "ar" => "Arabic"
    }
    |> Map.get(code, code)
  end
end
