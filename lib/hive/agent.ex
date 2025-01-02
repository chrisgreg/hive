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

  Configuration can be set in your config.exs:
  ```elixir
  config :hive,
    log_level: :debug,
    default_retry_attempts: 3,
    retry_backoff: :exponential
  ```
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
      use GenServer

      def start_link(init_arg) do
        GenServer.start_link(__MODULE__, init_arg, name: __MODULE__)
      end

      def init(state) do
        {:ok, state}
      end

      def process(input) do
        require Logger

        # Use framework's pipeline ID generator
        input =
          if Map.has_key?(input, :_pipeline_id) do
            input
          else
            Map.put(input, :_pipeline_id, Hive.generate_pipeline_id())
          end

        agent_name = __MODULE__ |> to_string() |> String.split(".") |> List.last()

        # Use configured log level
        Logger.log(
          Hive.log_level(),
          "Starting #{agent_name} (Pipeline ID: #{input[:_pipeline_id]})"
        )

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
            Logger.log(
              Hive.log_level(),
              "#{agent_name} completed with outcome: #{outcome}"
            )

            {outcome, data}

          {:ok, next_agent} ->
            next_agent_name = next_agent |> to_string() |> String.split(".") |> List.last()

            Logger.log(
              Hive.log_level(),
              "#{agent_name} forwarding to #{next_agent_name}"
            )

            data = Map.put(data, :_pipeline_id, pipeline_id)
            result = next_agent.process(data)

            if elem(result, 0) != outcome do
              Logger.log(
                Hive.log_level(),
                "#{agent_name} completed with outcome: #{elem(result, 0)}"
              )
            end

            result

          {:retry, opts} ->
            handle_retry(data, opts)

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

      defp handle_retry(data, opts \\ []) do
        require Logger

        pipeline_id = data[:_pipeline_id]
        attempt = Map.get(data, :_retry_attempt, 0) + 1

        # Use framework's default retry attempts if not specified in outcome
        max_attempts =
          opts
          |> Keyword.get(:max_attempts, Hive.default_retry_attempts())

        if attempt <= max_attempts do
          data = Map.put(data, :_retry_attempt, attempt)

          Logger.warning(
            "#{__MODULE__} retry attempt #{attempt}/#{max_attempts} (Pipeline ID: #{pipeline_id})"
          )

          # Use framework's backoff calculation
          delay = Hive.calculate_retry_delay(attempt)
          Process.sleep(delay)

          process(data)
        else
          {:error, "Max retry attempts (#{max_attempts}) exceeded"}
        end
      end
    end
  end
end
