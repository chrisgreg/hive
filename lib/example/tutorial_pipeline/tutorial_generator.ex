defmodule Example.TutorialGenerator do
  use Hive.Agent

  schema do
    input do
      field(:topic, :string, "The tutorial topic")
      field(:difficulty, :string, "The difficulty level")
      field(:max_length, :integer, "Maximum word count")
      field(:cache_key, :string, "The cache key for storage")
    end

    output do
      field(:topic, :string, "The tutorial topic")
      field(:difficulty, :string, "The difficulty level")
      field(:max_length, :integer, "Maximum word count")
      field(:cache_key, :string, "The cache key")
      field(:tutorial_content, :string, "Generated tutorial content")
      field(:metadata, :map, "Tutorial metadata including word count, sections, etc.")
    end
  end

  outcomes do
    outcome(:generated,
      to: Example.TutorialQualityValidator,
      description: "Tutorial successfully generated, proceed to quality validation"
    )

    outcome(:retry,
      to: __MODULE__,
      max_attempts: 3,
      description: "Generation failed, retry"
    )

    outcome(:error,
      to: Example.ErrorHandler,
      description: "Fatal error in generation"
    )
  end

  def handle_task(input) do
    case generate_tutorial_with_ai(input) do
      {:ok, content, metadata} ->
        {:generated,
         %{
           topic: input.topic,
           difficulty: input.difficulty,
           max_length: input.max_length,
           cache_key: input.cache_key,
           tutorial_content: content,
           metadata: metadata
         }}

      {:error, :api_error} ->
        {:retry, input}

      {:error, reason} ->
        {:error, %{reason: reason}}
    end
  end

  defp generate_tutorial_with_ai(input) do
    prompt = build_prompt(input)

    case Instructor.chat_completion(
           model: "gpt-4o-mini",
           response_model: TutorialResponse,
           messages: [%{role: "user", content: prompt}],
           max_retries: 2
         ) do
      {:ok, response} ->
        metadata = %{
          word_count: count_words(response.content),
          sections: response.sections,
          key_points: response.key_points,
          generated_at: DateTime.utc_now() |> to_string()
        }

        {:ok, response.content, metadata}

      {:error, _} ->
        {:error, :api_error}
    end
  end

  defp build_prompt(input) do
    """
    Create a comprehensive tutorial on: #{input.topic}

    Requirements:
    - Difficulty level: #{input.difficulty}
    - Maximum length: #{input.max_length} words
    - Structure: Include clear sections with headings
    - Style: Clear, instructional, and appropriate for the difficulty level

    The tutorial should include:
    1. An introduction explaining what will be covered
    2. Prerequisites (if any)
    3. Step-by-step instructions
    4. Tips and best practices
    5. Common mistakes to avoid
    6. A conclusion with next steps

    Format the tutorial with clear markdown headings and formatting.
    """
  end

  defp count_words(content) do
    content
    |> String.split(~r/\s+/)
    |> Enum.filter(&(&1 != ""))
    |> length()
  end
end

defmodule TutorialResponse do
  use Ecto.Schema
  use Instructor.Validator
  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field(:content, :string)
    field(:sections, {:array, :string})
    field(:key_points, {:array, :string})
  end

  @impl true
  def validate_changeset(changeset) do
    changeset
    |> validate_required([:content, :sections, :key_points])
    |> validate_length(:content, min: 100)
    |> validate_length(:sections, min: 3)
    |> validate_length(:key_points, min: 3)
  end
end
