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
      Module.register_attribute(__MODULE__, :llm_routing, accumulate: false)
      Module.register_attribute(__MODULE__, :llm_config, accumulate: false)
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

  ## Options
    * `:to` - The module to route to
    * `:max_attempts` - Maximum retry attempts
    * `:description` - Description of when this outcome should be chosen (for LLM routing)

  ## Example
      outcomes do
        outcome :success, to: NextModule, description: "Use when processing succeeds"
        outcome :retry, max_attempts: 3, description: "Use when a temporary error occurs"
      end
  """
  defmacro outcome(name, opts) do
    quote do
      @outcomes {unquote(name), unquote(opts)}
    end
  end

  defmacro llm_routing(do: block) do
    quote do
      @llm_routing true
      @llm_config unquote(block)
    end
  end

  # This macro is called after the module is defined to inject the necessary
  # GenServer implementation and helper functions
  defmacro __before_compile__(_env) do
    quote do
      use GenServer
      def __llm_config__, do: @llm_config
      def __outcomes__, do: @outcomes
      def __input_schema__, do: @input_schema
      def __output_schema__, do: @output_schema

      def start_link(init_arg) do
        GenServer.start_link(__MODULE__, init_arg, name: __MODULE__)
      end

      def init(state) do
        {:ok, state}
      end

      def process(input) do
        case Hive.Supervisor.start_pipeline(__MODULE__, input) do
          {:ok, pid} ->
            ref = Process.monitor(pid)

            receive do
              {:pipeline_result, result} ->
                Process.demonitor(ref)
                result

              {:DOWN, ^ref, :process, ^pid, _reason} ->
                {:error, :pipeline_crashed}
            end

          {:error, reason} ->
            {:error, reason}
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

        # First handle LLM routing if enabled
        {final_outcome, final_data} =
          if function_exported?(__MODULE__, :__llm_config__, 0) and __MODULE__.__llm_config__() do
            case Hive.LLM.Router.determine_outcome(__MODULE__, outcome, data) do
              {:ok, llm_outcome, llm_data} ->
                Logger.debug("#{agent_name} LLM chose outcome: #{llm_outcome}")
                {llm_outcome, Map.merge(data, llm_data)}

              {:error, reason} ->
                Logger.error("#{agent_name} LLM routing error: #{inspect(reason)}")
                {outcome, data}
            end
          else
            {outcome, data}
          end

        Logger.debug("#{agent_name} looking for outcome: #{inspect(final_outcome)}")
        Logger.debug("#{agent_name} available outcomes: #{inspect(__MODULE__.__outcomes__())}")

        # Find the matching outcome and its configuration
        case Enum.find(__MODULE__.__outcomes__(), fn {name, _opts} -> name == final_outcome end) do
          {_name, opts} ->
            case opts do
              # Handle routing to next module
              [{:to, next_module} | _] when not is_nil(next_module) ->
                Logger.debug("#{agent_name} routing to: #{inspect(next_module)}")
                next_module.process(final_data)

              # Handle retry with max attempts
              [{:max_attempts, max} | _] when is_integer(max) ->
                Logger.debug("#{agent_name} handling retry with max_attempts: #{max}")
                handle_retry(final_data, max_attempts: max)

              _ ->
                Logger.debug("#{agent_name} no routing configuration found")
                {final_outcome, final_data}
            end

          nil ->
            Logger.debug("#{agent_name} no matching outcome found")
            {final_outcome, final_data}
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
