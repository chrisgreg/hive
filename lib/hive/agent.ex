defmodule Hive.Agent do
  @moduledoc """
  Provides the core functionality for creating autonomous agents in the Hive framework.
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

  defmacro schema(do: block) do
    quote do
      unquote(block)
    end
  end

  defmacro input(do: block) do
    quote do
      @input_schema Hive.Schema.new(unquote(block))
    end
  end

  defmacro output(do: block) do
    quote do
      @output_schema Hive.Schema.new(unquote(block))
    end
  end

  defmacro outcomes(do: block) do
    quote do
      unquote(block)
    end
  end

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
