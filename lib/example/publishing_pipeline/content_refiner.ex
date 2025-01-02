defmodule Example.ContentRefiner do
  use Hive.Agent

  schema do
    input do
      field :content, :string, required: true
      field :metadata, :map, required: true
      field :similarity_score, :float, required: true
    end

    output do
      field :content, :string
      field :metadata, :map
      field :refinements, :map
    end
  end

  outcomes do
    outcome :refined, to: Example.Publisher
    outcome :retry, to: __MODULE__, max_attempts: 2
    outcome :error, to: Example.ErrorHandler
  end

  def handle_task(input) do
    case refine_content(input) do
      {:ok, refined_content, refinements} ->
        metadata = Map.merge(input.metadata, %{
          refined_at: DateTime.utc_now(),
          refinements: refinements
        })

        {:refined, %{
          content: refined_content,
          metadata: metadata,
          refinements: refinements
        }}

      {:error, :temporary_failure} ->
        {:retry, input}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp refine_content(%{content: content}) do
    # Simulate content refinement
    # In reality, this could use AI to improve quality, fix grammar, etc.
    refinements = %{
      grammar_fixes: 3,
      style_improvements: 2,
      clarity_enhancements: 1
    }

    refined = "Refined: #{content}"
    {:ok, refined, refinements}
  end
end
