defmodule Example.TutorialCacheWriter do
  use Hive.Agent

  schema do
    input do
      field(:topic, :string, "The tutorial topic")
      field(:difficulty, :string, "The difficulty level")
      field(:max_length, :integer, "Maximum word count")
      field(:cache_key, :string, "The cache key")
      field(:tutorial_content, :string, "The tutorial content")
      field(:metadata, :map, "Tutorial metadata")
      field(:quality_assessment, :map, "Quality assessment results")
    end

    output do
      field(:topic, :string, "The tutorial topic")
      field(:difficulty, :string, "The difficulty level")
      field(:tutorial_content, :string, "The final tutorial content")
      field(:metadata, :map, "Complete tutorial metadata")
      field(:cache_key, :string, "The cache key used for storage")
      field(:cached_at, :string, "When the tutorial was cached")
    end
  end

  outcomes do
    outcome(:cached,
      to: nil,
      description: "Tutorial successfully cached and returned"
    )

    outcome(:cache_error,
      to: Example.ErrorHandler,
      description: "Failed to cache the tutorial"
    )
  end

  def handle_task(input) do
    # Ensure cache manager is running
    Example.TutorialCacheManager.ensure_started()

    require Logger
    cached_at = DateTime.utc_now() |> to_string()

    # Prepare the data to cache
    cache_data = %{
      topic: input.topic,
      difficulty: input.difficulty,
      max_length: input.max_length,
      tutorial_content: input.tutorial_content,
      metadata:
        Map.merge(input.metadata, %{
          cached_at: cached_at,
          quality_assessment: input[:quality_assessment] || %{}
        })
    }

    # Store in ETS
    Logger.debug("TutorialCacheWriter: Attempting to cache with key: #{input.cache_key}")

    case :ets.insert(:tutorial_cache, {input.cache_key, cache_data}) do
      true ->
        Logger.debug("TutorialCacheWriter: Successfully cached tutorial")

        {:cached,
         Map.merge(cache_data, %{
           cache_key: input.cache_key,
           cached_at: cached_at
         })}

      false ->
        Logger.error("TutorialCacheWriter: Failed to cache tutorial")
        {:cache_error, %{reason: "Failed to insert into ETS table"}}
    end
  end
end
