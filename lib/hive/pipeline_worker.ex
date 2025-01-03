defmodule Hive.PipelineWorker do
  use GenServer
  require Logger

  def start_link({pipeline_module, input, parent}) do
    GenServer.start_link(__MODULE__, {pipeline_module, input, parent})
  end

  @impl true
  def init({pipeline_module, input, parent}) do
    {:ok, {pipeline_module, input, parent}, {:continue, :process}}
  end

  @impl true
  def handle_continue(:process, {module, input, parent}) do
    result = do_process(module, input)
    send(parent, {:pipeline_result, result})
    {:stop, :normal, result}
  end

  defp do_process(module, input) do
    # Add pipeline ID if not present
    input =
      if Map.has_key?(input, :_pipeline_id) do
        input
      else
        Map.put(input, :_pipeline_id, Hive.generate_pipeline_id())
      end

    agent_name = module |> to_string() |> String.split(".") |> List.last()

    Logger.log(
      Hive.log_level(),
      "Starting #{agent_name} (Pipeline ID: #{input[:_pipeline_id]})"
    )

    with :ok <- validate_input(module, input),
         {outcome, data} <- module.handle_task(input),
         :ok <- validate_output(module, data) do
      data = Map.put(data, :_pipeline_id, input[:_pipeline_id])
      route_outcome(module, {outcome, data}, input[:_pipeline_id])
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_input(module, input) do
    Hive.Schema.validate(module.__input_schema__(), input)
  end

  defp validate_output(module, output) do
    Hive.Schema.validate(module.__output_schema__(), output)
  end

  defp route_outcome(module, {outcome, data}, pipeline_id) do
    agent_name = module |> to_string() |> String.split(".") |> List.last()

    # Handle LLM routing if enabled
    {final_outcome, final_data} =
      if function_exported?(module, :__llm_config__, 0) and module.__llm_config__() do
        case Hive.LLM.Router.determine_outcome(module, outcome, data) do
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
    Logger.debug("#{agent_name} available outcomes: #{inspect(module.__outcomes__())}")

    # Find and handle the matching outcome
    case Enum.find(module.__outcomes__(), fn {name, _opts} -> name == final_outcome end) do
      {_name, opts} ->
        case opts do
          [{:to, next_module} | _] when not is_nil(next_module) ->
            Logger.debug("#{agent_name} routing to: #{inspect(next_module)}")
            next_module.process(final_data)

          [{:max_attempts, max} | _] when is_integer(max) ->
            Logger.debug("#{agent_name} handling retry with max_attempts: #{max}")
            handle_retry(module, final_data, max_attempts: max)

          _ ->
            Logger.debug("#{agent_name} no routing configuration found")
            {final_outcome, final_data}
        end

      nil ->
        Logger.debug("#{agent_name} no matching outcome found")
        {final_outcome, final_data}
    end
  end

  defp handle_retry(module, data, opts) do
    pipeline_id = data[:_pipeline_id]
    attempt = Map.get(data, :_retry_attempt, 0) + 1
    max_attempts = opts[:max_attempts] || Hive.default_retry_attempts()

    if attempt <= max_attempts do
      data = Map.put(data, :_retry_attempt, attempt)

      Logger.warning(
        "#{module} retry attempt #{attempt}/#{max_attempts} (Pipeline ID: #{pipeline_id})"
      )

      delay = Hive.calculate_retry_delay(attempt)
      Process.sleep(delay)

      module.process(data)
    else
      {:error, "Max retry attempts (#{max_attempts}) exceeded"}
    end
  end
end
