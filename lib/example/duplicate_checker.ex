defmodule Example.DuplicateChecker do
  use Hive.Agent

  schema do
    input do
      field(:content, :string, required: true)
      field(:metadata, :map, required: true)
    end

    output do
      field(:content, :string)
      field(:metadata, :map)
      field(:similarity_score, :float)
    end
  end

  outcomes do
    # Content is unique enough, proceed to refinement
    outcome(:unique, to: Example.ContentRefiner)
    # Content is too similar, generate new content
    outcome(:duplicate, to: Example.ContentGenerator)
    # Error handling
    outcome(:error, to: Example.ErrorHandler)
  end

  def handle_task(input) do
    case check_duplicates(input) do
      {:ok, similarity_score} when similarity_score < 0.8 ->
        {:unique, Map.put(input, :similarity_score, similarity_score)}

      {:ok, similarity_score} ->
        # Get original parameters from metadata
        topic = get_in(input, [:metadata, :topic]) || "unknown"
        length = get_in(input, [:metadata, :length]) || 500
        style = get_in(input, [:metadata, :style]) || "informative"

        {:duplicate,
         %{
           topic: topic,
           length: length,
           style: style,
           retry_reason: "Content similarity score: #{similarity_score}"
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp check_duplicates(%{content: content}) do
    # Simulate duplicate checking logic
    # In reality, this could use vector similarity, text comparison, etc.
    similarity_score = :rand.uniform()
    {:ok, similarity_score}
  end
end
