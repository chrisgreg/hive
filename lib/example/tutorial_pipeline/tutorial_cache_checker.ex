defmodule Example.TutorialCacheChecker do
  use Hive.Agent

  schema do
    input do
      field(:topic, :string, "The tutorial topic")
      field(:difficulty, :string, "The difficulty level")
      field(:max_length, :integer, "Maximum word count")
      field(:cache_key, :string, "The cache key to lookup")
    end

    output do
      field(:topic, :string, "The tutorial topic")
      field(:difficulty, :string, "The difficulty level")
      field(:max_length, :integer, "Maximum word count")
      field(:cache_key, :string, "The cache key")
      field(:tutorial_content, :string, "Cached tutorial content if found")
      field(:metadata, :map, "Tutorial metadata")
      field(:cached, :boolean, "Whether this was retrieved from cache")
    end
  end

  outcomes do
    outcome(:cache_hit,
      to: nil,
      description: "Tutorial found in cache, return it directly"
    )

    outcome(:cache_miss,
      to: Example.TutorialGenerator,
      description: "Tutorial not in cache, proceed to generate"
    )
  end

  def handle_task(input) do
    # Ensure cache manager is running
    Example.TutorialCacheManager.ensure_started()

    require Logger

    case :ets.lookup(:tutorial_cache, input.cache_key) do
      [{_key, tutorial_data}] ->
        Logger.debug("TutorialCacheChecker: Cache HIT for key: #{input.cache_key}")
        # Found in cache - return it
        {:cache_hit,
         Map.merge(tutorial_data, %{
           cached: true,
           cache_key: input.cache_key
         })}

      [] ->
        Logger.debug("TutorialCacheChecker: Cache MISS for key: #{input.cache_key}")
        # Not in cache - pass through to generator
        {:cache_miss,
         Map.merge(input, %{
           cached: false
         })}
    end
  end
end
