defmodule Hive.LLM.Router do
  @moduledoc """
  Handles LLM-based routing decisions for Hive agents
  """

  defmodule Decision do
    use Ecto.Schema
    use Instructor.Validator

    @primary_key false
    embedded_schema do
      field(:outcome, :string)
      field(:reasoning, :string)
      field(:next_step, :string)
    end
  end

  def determine_outcome(agent_module, current_outcome, data) do
    config = agent_module.__llm_config__()
    outcomes = agent_module.__outcomes__() |> IO.inspect()

    prompt = build_prompt(config, current_outcome, data, outcomes)

    case Instructor.chat_completion(
           model: config[:model] || "gpt-3.5-turbo",
           response_model: Decision,
           messages: [%{role: "user", content: prompt}]
         ) do
      {:ok, decision} ->
        # Validate the chosen outcome exists
        outcome = String.to_atom(decision.outcome) |> IO.inspect()

        if Enum.any?(outcomes, fn {name, _} -> name == outcome end) do
          {:ok, outcome, Map.put(data, :llm_reasoning, decision.reasoning)}
        else
          {:error, "LLM chose invalid outcome: #{outcome}"}
        end

      error ->
        error
    end
  end

  defp build_prompt(config, current_outcome, data, outcomes) do
    custom_prompt = config[:prompt]

    outcome_descriptions =
      Enum.map(outcomes, fn {name, opts} ->
        "- #{name}: #{opts[:description] || "No description provided"}"
      end)

    """
    #{custom_prompt || "Determine the next step in the pipeline."}

    Current outcome: #{current_outcome}
    Current data: #{inspect(data)}

    Available outcomes:
    #{Enum.join(outcome_descriptions, "\n")}

    Provide your decision in the following format:
    - outcome: The selected outcome name
    - reasoning: A brief explanation of why this outcome was chosen
    - next_step: The name of the next agent to process this data (or 'nil' if it's the end)
    """
  end
end
