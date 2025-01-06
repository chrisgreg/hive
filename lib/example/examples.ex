defmodule Examples do
  @moduledoc """
  This module contains example functions demonstrating the usage of the Hive framework.
  These examples can be run in IEx to see Hive in action.
  """

  @doc """
  Runs the greeting pipeline example.

  ## Example

      iex> Example.run_greeter("es", "Maria")
      {:complete, %{formatted_message: "¡HOLA MARIA", ...}}

      iex> Example.run_greeter("fr", "Jean")
      {:complete, %{formatted_message: "BONJOUR JEAN", ...}}

      iex> Example.run_greeter("de", "Hans")
      {:unsupported_language, %{unsupported_language: "de"}}
  """
  def run_greeter(language, name) do
    Example.Greeter.process(%{
      language: language,
      name: name
    })
  end

  @doc """
  Runs the content generation and publishing pipeline.

  ## Example

      iex> Example.run_content_pipeline("Elixir", 500, "technical")
      {:published, %{url: "https://example.com/content/...", published_at: ~U[...], status: "published"}}
  """
  def run_content_pipeline(topic, length \\ 500, style \\ "informative") do
    Example.ContentGenerator.process(%{
      topic: topic,
      length: length,
      style: style
    })
  end

  @doc """
  Runs the content filtering pipeline with LLM-based moderation.

  ## Example

      iex> Example.run_content_filter("Hello, this is a friendly message!")
      {:pass, %{spam?: false, reasoning: "Content is appropriate and friendly"}}

      iex> Example.run_content_filter("You're an idiot!")
      {:filter, %{spam?: true, reasoning: "Content contains offensive language"}}
  """
  def run_profanity_filter(content) do
    Example.ContentFilterIdentifier.process(%{
      content: content
    })
  end

  @doc """
  Runs the tutorial generation pipeline with AI-powered content creation and caching.

  ## Example

      iex> Examples.run_tutorial_generator("How to bake bread", "beginner", 1000)
      {:cached, %{
        topic: "How to bake bread",
        difficulty: "beginner",
        tutorial_content: "# How to Bake Bread\\n\\n## Introduction...",
        metadata: %{...},
        cached_at: "2024-01-15 10:30:00"
      }}

      # Running the same request again will return cached result
      iex> Examples.run_tutorial_generator("How to bake bread", "beginner", 1000)
      {:cache_hit, %{cached: true, ...}}
  """
  def run_tutorial_generator(topic, difficulty \\ "beginner", max_length \\ 1000) do
    Example.TutorialRequestValidator.process(%{
      topic: topic,
      difficulty: difficulty,
      max_length: max_length
    })
  end

  @doc """
  Clears the tutorial cache. Useful for testing.

  ## Example

      iex> Examples.clear_tutorial_cache()
      :ok
  """
  def clear_tutorial_cache do
    Example.TutorialCacheManager.clear_cache()
  end

  @doc """
  Shows statistics about the tutorial cache.

  ## Example

      iex> Examples.tutorial_cache_stats()
      %{exists: true, size: 2, memory: 1024}
  """
  def tutorial_cache_stats do
    Example.TutorialCacheManager.cache_stats()
  end

  @doc """
  Lists all cached tutorial keys.

  ## Example

      iex> Examples.list_cached_tutorials()
      ["tutorial:how_to_bake_bread:beginner:1000", ...]
  """
  def list_cached_tutorials do
    Example.TutorialCacheManager.list_cached_keys()
  end
end
