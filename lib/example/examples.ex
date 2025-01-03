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
end
