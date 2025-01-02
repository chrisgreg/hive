defmodule Example.ContentGenerator do
  use Hive.Agent

  # Define the schema for inputs and outputs
  schema do
    input do
      field(:topic, :string, required: true)
      field(:length, :integer, default: 500)
      field(:style, :string, default: "informative")
    end

    output do
      field(:content, :string)
      field(:metadata, :map)
    end
  end

  # Define possible outcomes and their handlers
  outcomes do
    # Success path
    outcome(:generated, to: Example.DuplicateChecker)
    # Retry path if API fails
    outcome(:retry, to: __MODULE__, max_attempts: 3)
    # Error path
    outcome(:error, to: Example.ErrorHandler)
  end

  # Main task handler
  def handle_task(input) do
    case generate_content(input) do
      {:ok, content, metadata} ->
        metadata =
          if input[:retry_reason] do
            Map.put(metadata, :previous_rejection_reason, input.retry_reason)
          else
            metadata
          end

        {:generated, %{content: content, metadata: metadata}}

      {:error, :api_error} ->
        {:retry, input}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp generate_content(%{topic: topic, length: length, style: style} = input) do
    # Simulated API call to content generation service
    case simulate_api_call(topic, length, style) do
      {:ok, content} ->
        metadata = %{
          generated_at: DateTime.utc_now(),
          word_count: String.split(content, " ") |> length(),
          topic: topic,
          style: style,
          length: length,
          attempt: Map.get(input, :attempt, 1)
        }

        {:ok, content, metadata}

      error ->
        error
    end
  end

  defp simulate_api_call(topic, length, style) do
    # Simulate API success/failure
    if :rand.uniform() > 0.2 do
      {:ok, "Generated content about #{topic} in #{style} style with #{length} words..."}
    else
      {:error, :api_error}
    end
  end
end
