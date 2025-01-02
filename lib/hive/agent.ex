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

  # When a module uses Hive.Agent, this macro sets up the necessary imports and module attributes
  defmacro __using__(_opts) do
    quote do
      import Hive.Agent
      import Hive.Schema, only: [field: 2, field: 3]
      @before_compile Hive.Agent

      # Register module attributes for storing schemas and outcomes
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
  """
  defmacro input(do: block) do
    quote do
      @input_schema Hive.Schema.new(unquote(block))
    end
  end

  @doc """
  Defines the output schema for the agent.
  """
  defmacro output(do: block) do
    quote do
      @output_schema Hive.Schema.new(unquote(block))
    end
  end

  @doc """
  Defines a block for declaring possible outcomes of the agent.
  """
  defmacro outcomes(do: block) do
    quote do
      unquote(block)
    end
  end

  @doc """
  Defines a single outcome and its routing or configuration.
  """
  defmacro outcome(name, opts) do
    quote do
      @outcomes {unquote(name), unquote(opts)}
    end
  end

  # This macro is called after the module is defined to inject the necessary
  # GenServer implementation and helper functions
  defmacro __before_compile__(_env) do
    quote do
      # Make the agent a GenServer for potential distributed processing
      use GenServer

      # Standard GenServer callbacks
      def start_link(init_arg) do
        GenServer.start_link(__MODULE__, init_arg, name: __MODULE__)
      end

      def init(state) do
        {:ok, state}
      end

      # Main entry point for processing data through the agent
      def process(input) do
        require Logger

        # Ensure each pipeline execution has a unique ID for tracking
        input =
          if Map.has_key?(input, :_pipeline_id) do
            input
          else
            Map.put(input, :_pipeline_id, System.unique_integer([:positive, :monotonic]))
          end

        # Log the start of processing for this agent
        agent_name = __MODULE__ |> to_string() |> String.split(".") |> List.last()
        Logger.debug("Starting #{agent_name} Hive Pipeline ID: #{input[:_pipeline_id]})")

        # Execute the processing pipeline with validation
        with :ok <- validate_input(input),
             {outcome, data} <- handle_task(input),
             :ok <- validate_output(data) do
          # Preserve pipeline ID in the output
          data = Map.put(data, :_pipeline_id, input[:_pipeline_id])
          route_outcome({outcome, data}, input[:_pipeline_id])
        else
          {:error, reason} -> {:error, reason}
        end
      end

      # Validate input data against the input schema
      defp validate_input(input) do
        Hive.Schema.validate(@input_schema, input)
      end

      # Validate output data against the output schema
      defp validate_output(output) do
        Hive.Schema.validate(@output_schema, output)
      end

      # Handle routing of outcomes to the next agent in the pipeline
      defp route_outcome({outcome, data}, pipeline_id) do
        require Logger
        agent_name = __MODULE__ |> to_string() |> String.split(".") |> List.last()

        case find_outcome_route(outcome) do
          {:ok, nil} ->
            # End of pipeline - return the final result
            Logger.debug("#{agent_name} completed with outcome: #{outcome}")
            {outcome, data}

          {:ok, next_agent} ->
            # Forward to the next agent in the pipeline
            next_agent_name = next_agent |> to_string() |> String.split(".") |> List.last()
            Logger.debug("#{agent_name} forwarding to #{next_agent_name}")

            # Preserve pipeline ID when forwarding
            data = Map.put(data, :_pipeline_id, pipeline_id)
            result = next_agent.process(data)

            # Log completion if outcome changed
            if elem(result, 0) != outcome do
              Logger.debug("#{agent_name} completed with outcome: #{elem(result, 0)}")
            end

            result

          {:retry, _opts} ->
            # Handle retry logic
            handle_retry(data)

          {:error, reason} ->
            # Log and return errors
            Logger.error("#{agent_name} failed: #{inspect(reason)}")
            {:error, reason}
        end
      end

      # Look up the routing configuration for a given outcome
      defp find_outcome_route(outcome) do
        case Enum.find(@outcomes, fn {name, _opts} -> name == outcome end) do
          {_name, opts} -> {:ok, opts[:to]}
          nil -> {:error, :unknown_outcome}
        end
      end

      # Handle retry logic with exponential backoff
      defp handle_retry(data) do
        require Logger

        pipeline_id = data[:_pipeline_id]
        attempt = Map.get(data, :_retry_attempt, 0) + 1

        # Get max attempts from retry outcome configuration
        max_attempts =
          Enum.find(@outcomes, fn {name, _} -> name == :retry end)
          |> elem(1)
          |> Keyword.get(:max_attempts, 3)

        if attempt <= max_attempts do
          data = Map.put(data, :_retry_attempt, attempt)
          Logger.warning("Retry attempt #{attempt}/#{max_attempts}")
          # Simple backoff delay - could be made more sophisticated
          Process.sleep(1000)
          process(data)
        else
          {:error, "Max retry attempts (#{max_attempts}) exceeded"}
        end
      end
    end
  end
end
