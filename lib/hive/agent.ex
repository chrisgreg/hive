defmodule Hive.Agent do
  @moduledoc """
  Provides the core functionality for creating autonomous agents in the Hive framework.

  Hive.Agent allows you to create autonomous agents that can process data, make decisions,
  and route outcomes to other agents in a pipeline. Each agent can define its input/output
  schemas and possible outcomes.

  ## Example
  ```elixir
  defmodule MyApp.ContentGenerator do
    use Hive.Agent

    input do
      field :prompt, :string, required: true
      field :max_length, :integer, default: 1000
    end

    output do
      field :content, :string
      field :metadata, :map
    end

    outcomes do
      outcome :success, to: MyApp.ContentRefiner
      outcome :error, to: MyApp.ErrorHandler
      outcome :retry, max_attempts: 3
    end

    def handle_task(input) do
      # Process the input and generate content
      case generate_content(input) do
        {:ok, content} ->
          {:success, %{content: content, metadata: %{generated_at: DateTime.utc_now()}}}
        {:error, _reason} ->
          {:retry, %{}}
      end
    end

    defp generate_content(_input) do
      # Implementation
    end
  end  ```

  ## Agent Configuration

  Each agent requires:

  1. Input schema - defines expected input fields and their types
  2. Output schema - defines the structure of the output data
  3. Outcomes - defines possible outcomes and their routing
  4. handle_task/1 function - implements the agent's core logic

  ## Pipeline Execution

  Agents are typically executed in a pipeline where the output of one agent becomes
  the input for the next agent based on the outcome routing:
  ```elixir
  MyApp.ContentGenerator.process(%{prompt: "Generate a blog post about Elixir"})  ```

  ## Automatic Features

  - Input/output validation based on schemas
  - Automatic retry handling with configurable attempts
  - Pipeline ID tracking across the agent chain
  - Debug logging of agent execution flow
  """

  defmacro __using__(_opts) do
    quote do
      import Hive.Agent
      import Hive.Schema, only: [field: 2, field: 3]
      @before_compile Hive.Agent

      Module.register_attribute(__MODULE__, :input_schema, accumulate: false)
      Module.register_attribute(__MODULE__, :output_schema, accumulate: false)
      Module.register_attribute(__MODULE__, :outcomes, accumulate: true)
    end
  end

  @doc """
  Defines a schema block for input or output schema definition.

  This is an internal macro used by `input/1` and `output/1`.
  """
  defmacro schema(do: block) do
    quote do
      unquote(block)
    end
  end

  @doc """
  Defines the input schema for the agent.

  ## Example

      input do
        field :name, :string, required: true
        field :age, :integer, default: 0
        field :metadata, :map
      end
  """
  defmacro input(do: block) do
    quote do
      @input_schema Hive.Schema.new(unquote(block))
    end
  end

  @doc """
  Defines the output schema for the agent.

  ## Example

      output do
        field :result, :string
        field :processed_at, :datetime
        field :status, :atom
      end
  """
  defmacro output(do: block) do
    quote do
      @output_schema Hive.Schema.new(unquote(block))
    end
  end

  @doc """
  Defines a block for declaring possible outcomes of the agent.

  ## Example

      outcomes do
        outcome :success, to: NextAgent
        outcome :error, to: ErrorHandler
        outcome :retry, max_attempts: 3
      end
  """
  defmacro outcomes(do: block) do
    quote do
      unquote(block)
    end
  end

  @doc """
  Defines a single outcome and its routing or configuration.

  ## Options

    * `:to` - The next agent module to route to for this outcome
    * `:max_attempts` - For retry outcomes, maximum number of retry attempts

  ## Example

      outcome :success, to: MyApp.NextAgent
      outcome :retry, max_attempts: 3
  """
  defmacro outcome(name, opts) do
    quote do
      @outcomes {unquote(name), unquote(opts)}
    end
  end

  defmacro __before_compile__(_env) do
    quote do
      use GenServer

      def start_link(init_arg) do
        GenServer.start_link(__MODULE__, init_arg, name: __MODULE__)
      end

      def init(state) do
        {:ok, state}
      end

      def process(input) do
        require Logger
        # Generate a unique ID for this pipeline execution if not present
        input =
          if Map.has_key?(input, :_pipeline_id) do
            input
          else
            Map.put(input, :_pipeline_id, System.unique_integer([:positive, :monotonic]))
          end

        agent_name = __MODULE__ |> to_string() |> String.split(".") |> List.last()
        Logger.debug("Starting #{agent_name} Hive Pipeline ID: #{input[:_pipeline_id]})")

        with :ok <- validate_input(input),
             {outcome, data} <- handle_task(input),
             :ok <- validate_output(data) do
          data = Map.put(data, :_pipeline_id, input[:_pipeline_id])
          route_outcome({outcome, data}, input[:_pipeline_id])
        else
          {:error, reason} -> {:error, reason}
        end
      end

      defp validate_input(input) do
        Hive.Schema.validate(@input_schema, input)
      end

      defp validate_output(output) do
        Hive.Schema.validate(@output_schema, output)
      end

      defp route_outcome({outcome, data}, pipeline_id) do
        require Logger
        agent_name = __MODULE__ |> to_string() |> String.split(".") |> List.last()

        case find_outcome_route(outcome) do
          {:ok, nil} ->
            # Log completion before returning final result
            Logger.debug("#{agent_name} completed with outcome: #{outcome}")
            {outcome, data}

          {:ok, next_agent} ->
            # Log that we're forwarding to next agent
            next_agent_name = next_agent |> to_string() |> String.split(".") |> List.last()
            Logger.debug("#{agent_name} forwarding to #{next_agent_name}")

            # Preserve the pipeline ID when forwarding
            data = Map.put(data, :_pipeline_id, pipeline_id)

            # Process in next agent
            result = next_agent.process(data)

            # Only log our completion if the outcome changed
            if elem(result, 0) != outcome do
              Logger.debug("#{agent_name} completed with outcome: #{elem(result, 0)}")
            end

            result

          {:retry, _opts} ->
            handle_retry(data)

          {:error, reason} ->
            Logger.error("#{agent_name} failed: #{inspect(reason)}")
            {:error, reason}
        end
      end

      defp find_outcome_route(outcome) do
        case Enum.find(@outcomes, fn {name, _opts} -> name == outcome end) do
          {_name, opts} -> {:ok, opts[:to]}
          nil -> {:error, :unknown_outcome}
        end
      end

      defp handle_retry(data) do
        require Logger

        pipeline_id = data[:_pipeline_id]
        attempt = Map.get(data, :_retry_attempt, 0) + 1

        max_attempts =
          Enum.find(@outcomes, fn {name, _} -> name == :retry end)
          |> elem(1)
          |> Keyword.get(:max_attempts, 3)

        if attempt <= max_attempts do
          data = Map.put(data, :_retry_attempt, attempt)
          Logger.warning("Retry attempt #{attempt}/#{max_attempts}")
          # Backoff delay
          Process.sleep(1000)
          process(data)
        else
          {:error, "Max retry attempts (#{max_attempts}) exceeded"}
        end
      end
    end
  end
end
