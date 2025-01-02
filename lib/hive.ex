defmodule Hive do
  @moduledoc """
  Hive is a framework for building autonomous agent pipelines in Elixir.

  It provides a structured way to create interconnected agents that can process data,
  make decisions, and handle errors gracefully. Each agent in a pipeline can validate
  its inputs/outputs and route outcomes to other agents.

  ## Basic Usage

  ```elixir
  defmodule MyApp.SimpleAgent do
    use Hive.Agent

    input do
      field :name, :string, required: true
    end

    output do
      field :greeting, :string
    end

    outcomes do
      outcome :success, to: nil
    end

    def handle_task(input) do
      {:success, %{greeting: "Hello, \#{input.name}!"}}
    end
  end

  # Process data through the agent
  MyApp.SimpleAgent.process(%{name: "Alice"})
  ```

  ## Configuration

  You can configure Hive in your application's config:

  ```elixir
  config :hive,
    log_level: :debug,  # Set logging level for pipeline execution
    default_retry_attempts: 3,  # Default number of retry attempts
    retry_backoff: :exponential  # :linear or :exponential backoff
  ```

  ## Features

  - Schema-based input/output validation
  - Automatic retry handling
  - Pipeline tracking with unique IDs
  - Debug logging of execution flow
  - Flexible outcome routing
  """

  @doc """
  Returns the current version of Hive.
  """
  def version do
    "0.1.0"
  end

  @doc """
  Returns the configured log level for Hive operations.

  ## Examples

      iex> Hive.log_level()
      :debug
  """
  def log_level do
    Application.get_env(:hive, :log_level, :debug)
  end

  @doc """
  Returns the default number of retry attempts for agents.

  ## Examples

      iex> Hive.default_retry_attempts()
      3
  """
  def default_retry_attempts do
    Application.get_env(:hive, :default_retry_attempts, 3)
  end

  @doc """
  Returns the configured retry backoff strategy.
  Can be :linear or :exponential.

  ## Examples

      iex> Hive.retry_backoff()
      :exponential
  """
  def retry_backoff do
    Application.get_env(:hive, :retry_backoff, :exponential)
  end

  @doc """
  Calculates the delay for a retry attempt based on the configured backoff strategy.

  ## Parameters

    - attempt: The current attempt number (1-based)
    - base_delay: The base delay in milliseconds (default: 1000)

  ## Examples

      iex> Hive.calculate_retry_delay(1)
      1000

      iex> Hive.calculate_retry_delay(3)
      4000  # With exponential backoff
  """
  def calculate_retry_delay(attempt, base_delay \\ 1000) do
    case retry_backoff() do
      :linear -> attempt * base_delay
      :exponential -> trunc(:math.pow(2, attempt - 1) * base_delay)
    end
  end

  @doc """
  Returns a new pipeline ID.
  This is used internally by agents to track pipeline execution.

  ## Examples

      iex> pipeline_id = Hive.generate_pipeline_id()
      iex> is_integer(pipeline_id)
      true
  """
  def generate_pipeline_id do
    System.unique_integer([:positive, :monotonic])
  end

  @doc """
  Starts the Hive application and any required dependencies.
  """
  def start do
    # In the future, this could start supervision trees or required services
    :ok
  end

  @doc """
  Stops the Hive application and cleans up any resources.
  """
  def stop do
    # In the future, this could handle cleanup of resources
    :ok
  end
end
