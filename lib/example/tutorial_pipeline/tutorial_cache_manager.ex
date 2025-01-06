defmodule Example.TutorialCacheManager do
  @moduledoc """
  Manages the ETS table for tutorial caching.
  This GenServer owns the ETS table to ensure it persists across different process calls.
  """

  use GenServer
  require Logger

  def start_link(_) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def init(:ok) do
    # Create the ETS table owned by this process
    table = :ets.new(:tutorial_cache, [:named_table, :public, :set, {:keypos, 1}])
    Logger.info("TutorialCacheManager: Created ETS table :tutorial_cache")
    {:ok, table}
  end

  @doc """
  Ensures the cache manager is running and the table exists
  """
  def ensure_started do
    case Process.whereis(__MODULE__) do
      nil ->
        # Start the cache manager if it's not running
        {:ok, _pid} = start_link(nil)
        :ok

      _pid ->
        :ok
    end
  end

  @doc """
  Get stats about the cache
  """
  def cache_stats do
    case :ets.whereis(:tutorial_cache) do
      :undefined ->
        %{exists: false, size: 0}

      _tid ->
        %{
          exists: true,
          size: :ets.info(:tutorial_cache, :size),
          memory: :ets.info(:tutorial_cache, :memory)
        }
    end
  end

  @doc """
  Clear all cached tutorials
  """
  def clear_cache do
    case :ets.whereis(:tutorial_cache) do
      :undefined ->
        :ok

      _tid ->
        :ets.delete_all_objects(:tutorial_cache)
        Logger.info("TutorialCacheManager: Cleared all cached tutorials")
        :ok
    end
  end

  @doc """
  List all cached tutorial keys
  """
  def list_cached_keys do
    case :ets.whereis(:tutorial_cache) do
      :undefined ->
        []

      _tid ->
        :ets.select(:tutorial_cache, [{{:"$1", :_}, [], [:"$1"]}])
    end
  end
end
