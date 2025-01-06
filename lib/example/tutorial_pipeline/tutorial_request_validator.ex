defmodule Example.TutorialRequestValidator do
  use Hive.Agent

  schema do
    input do
      field(:topic, :string, "The topic for the tutorial (e.g., 'How to bake bread')")
      field(:difficulty, :string, "The difficulty level: beginner, intermediate, or advanced")
      field(:max_length, :integer, "Maximum word count for the tutorial")
    end

    output do
      field(:topic, :string, "Validated and normalized topic")
      field(:difficulty, :string, "Validated difficulty level")
      field(:max_length, :integer, "Validated max length")
      field(:cache_key, :string, "Generated cache key for this tutorial")
    end
  end

  outcomes do
    outcome(:valid,
      to: Example.TutorialCacheChecker,
      description: "Input is valid, proceed to check cache"
    )

    outcome(:invalid,
      to: Example.ErrorHandler,
      description: "Input validation failed"
    )
  end

  def handle_task(input) do
    with {:ok, difficulty} <- validate_difficulty(input[:difficulty]),
         {:ok, length} <- validate_length(input[:max_length]),
         {:ok, topic} <- validate_topic(input[:topic]) do
      # Generate a cache key based on normalized values
      cache_key = generate_cache_key(topic, difficulty, length)

      {:valid,
       %{
         topic: topic,
         difficulty: difficulty,
         max_length: length,
         cache_key: cache_key
       }}
    else
      {:error, reason} ->
        {:invalid, %{reason: reason}}
    end
  end

  defp validate_difficulty(difficulty)
       when difficulty in ["beginner", "intermediate", "advanced"] do
    {:ok, difficulty}
  end

  defp validate_difficulty(nil), do: {:ok, "beginner"}

  defp validate_difficulty(_),
    do: {:error, "Invalid difficulty level. Must be beginner, intermediate, or advanced"}

  defp validate_length(length) when is_integer(length) and length > 100 and length <= 5000 do
    {:ok, length}
  end

  defp validate_length(nil), do: {:ok, 1000}
  defp validate_length(_), do: {:error, "Length must be between 100 and 5000 words"}

  defp validate_topic(topic) when is_binary(topic) and byte_size(topic) > 5 do
    {:ok, String.trim(topic)}
  end

  defp validate_topic(_), do: {:error, "Topic must be at least 5 characters long"}

  defp generate_cache_key(topic, difficulty, max_length) do
    # Create a normalized cache key
    normalized_topic =
      topic
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9\s]/, "")
      |> String.replace(~r/\s+/, "_")

    "tutorial:#{normalized_topic}:#{difficulty}:#{max_length}"
  end
end
