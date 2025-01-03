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

    prompt =
      build_prompt(config, current_outcome, data, outcomes)

    case Instructor.chat_completion(
           model: config[:model] || "gpt-4o-mini",
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
    outcome_descriptions =
      outcomes
      |> Enum.map(fn {name, opts} ->
        description = Keyword.get(opts, :description, "No description provided")
        "- #{name}: #{description}"
      end)
      |> Enum.join("\n")

    """
    #{config[:prompt]}

    Available outcomes:
    #{outcome_descriptions}

    Current data:
    #{inspect(data)}

    Choose the most appropriate outcome based on the above information.
    """
    |> IO.inspect()
  end
end
