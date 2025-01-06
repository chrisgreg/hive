defmodule Example.TutorialQualityValidator do
  use Hive.Agent

  schema do
    input do
      field(:topic, :string, "The tutorial topic")
      field(:difficulty, :string, "The difficulty level")
      field(:max_length, :integer, "Maximum word count")
      field(:cache_key, :string, "The cache key")
      field(:tutorial_content, :string, "Generated tutorial content")
      field(:metadata, :map, "Tutorial metadata")
    end

    output do
      field(:topic, :string, "The tutorial topic")
      field(:difficulty, :string, "The difficulty level")
      field(:max_length, :integer, "Maximum word count")
      field(:cache_key, :string, "The cache key")
      field(:tutorial_content, :string, "The tutorial content")
      field(:metadata, :map, "Enhanced metadata with quality scores")
      field(:quality_assessment, :map, "Detailed quality assessment")
    end
  end

  outcomes do
    outcome(:approved,
      to: Example.TutorialCacheWriter,
      description: "Tutorial meets quality standards, proceed to cache it"
    )

    outcome(:needs_revision,
      to: Example.TutorialGenerator,
      description: "Tutorial needs improvement, regenerate with feedback"
    )

    outcome(:rejected,
      to: Example.ErrorHandler,
      description: "Tutorial quality is too poor to fix"
    )
  end

  llm_routing do
    [
      model: "gpt-4o-mini",
      prompt: """
      Evaluate the quality of this tutorial based on these criteria:

      1. Completeness: Does it cover all necessary aspects of the topic?
      2. Clarity: Is it easy to understand for the target difficulty level?
      3. Structure: Is it well-organized with clear sections?
      4. Accuracy: Is the information correct and up-to-date?
      5. Length: Is it within the requested word count limit?

      Consider:
      - Topic: {topic}
      - Difficulty: {difficulty}
      - Max Length: {max_length} words
      - Actual Word Count: {word_count}

      Tutorial Content:
      {tutorial_content}

      If the tutorial has minor issues that could be fixed with regeneration, choose 'needs_revision'.
      If the tutorial is good quality and ready to use, choose 'approved'.
      If the tutorial has fundamental issues that can't be easily fixed, choose 'rejected'.
      """
    ]
  end

  def handle_task(input) do
    # First, perform basic validation
    word_count = input.metadata[:word_count] || 0

    cond do
      word_count > input.max_length * 1.2 ->
        # Way too long, needs revision
        {:needs_revision,
         Map.merge(input, %{
           revision_reason: "Tutorial exceeds maximum length by more than 20%"
         })}

      word_count < 100 ->
        # Too short to be useful
        {:rejected, %{reason: "Tutorial is too short (less than 100 words)"}}

      true ->
        # Let LLM make the quality decision
        # Return default outcome that will be overridden by LLM
        {:approved,
         Map.merge(input, %{
           quality_assessment: %{
             word_count_ok: word_count <= input.max_length,
             actual_word_count: word_count
           }
         })}
    end
  end
end
