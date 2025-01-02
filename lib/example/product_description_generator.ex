defmodule Example.ProductDescriptionGenerator do
  use Hive.Agent

  schema do
    input do
      field(:product_name, :string, required: true)
      field(:category, :string, required: true)
      field(:key_features, {:array, :string}, required: true)
      field(:tone, :string, default: "professional")
    end

    output do
      field(:description, :string)
      field(:metadata, :map)
    end
  end

  outcomes do
    outcome(:generated, to: nil)
    outcome(:retry, to: __MODULE__, max_attempts: 3)
    outcome(:error, to: Example.ErrorHandler)
  end

  llm_routing do
    [
      model: "gpt-4o-mini",
      prompt: """
      Analyze the generated product description and determine if it should proceed
      to validation or if there was an error in generation.
      Consider:
      1. Was the description generated successfully?
      2. Does it include the key features?
      3. Does it match the requested tone?
      """
    ]
  end

  def handle_task(input) do
    IO.inspect(input)

    case generate_description(input) do
      {:ok, description} ->
        metadata = %{
          generated_at: DateTime.utc_now(),
          word_count: description |> String.split() |> length(),
          tone: input.tone,
          original_features: input.key_features
        }

        {:generated,
         %{
           description: description,
           metadata: metadata
         }}

      {:error, reason} ->
        {:error, %{reason: reason}}
    end
  end

  defp generate_description(input) do
    # In a real implementation, this would use Instructor to generate the description
    # For this example, we'll simulate it
    description = """
    Introducing the #{input.product_name} - a revolutionary addition to our #{input.category} line.
    #{Enum.map_join(input.key_features, " ", &"#{&1}.")}
    """

    {:ok, description}
  end
end
