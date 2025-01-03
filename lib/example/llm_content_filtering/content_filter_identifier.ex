defmodule Example.ContentFilterIdentifier do
  use Hive.Agent

  schema do
    input do
      field(:content, :string, required: true)
    end

    output do
      field(:spam?, :boolean)
      field(:reasoning, :string)
    end
  end

  outcomes do
    outcome(:filter, to: Example.ContentFilterIdentifier.Filter)
    outcome(:pass, to: Example.ContentFilterIdentifier.Pass)
    outcome(:retry, to: __MODULE__, max_attempts: 3)
    outcome(:error, to: Example.ErrorHandler)
  end

  llm_routing do
    [
      model: "gpt-4o-mini",
      prompt: """
      Assess if the content is rude or offensive.
      Provide a succinct reasoning for your decision.

      If the content is rude or offensive, the user will be banned - in your reasoning, address the user and the reason for the ban.

      Swearing is allowed, but only if it's to emphasize a point.
      """
    ]
  end

  def handle_task(input) do
    case Hive.LLM.Router.determine_outcome(__MODULE__, :initial, input) do
      {:ok, :pass, data} ->
        {:pass,
         %{
           content: input.content,
           spam?: false,
           reasoning: data.llm_reasoning
         }}

      {:ok, :filter, data} ->
        {:filter,
         %{
           content: input.content,
           spam?: true,
           reasoning: data.llm_reasoning
         }}

      {:ok, :error, data} ->
        {:error, %{reason: data.llm_reasoning}}

      {:error, reason} ->
        {:error, %{reason: reason}}
    end
  end
end

defmodule Example.ContentFilterIdentifier.Pass do
  use Hive.Agent

  schema do
    input do
      field(:content, :string)
    end

    output do
      field(:status, :string)
      field(:processed_at, :string)
    end
  end

  outcomes do
    outcome(:complete, to: nil)
  end

  def handle_task(input) do
    # Store the content in the database
    {:comment_valid,
     %{
       content: input.content,
       processed_at: DateTime.utc_now() |> to_string()
     }}
  end
end

defmodule Example.ContentFilterIdentifier.Filter do
  use Hive.Agent

  schema do
    input do
      field(:spam?, :boolean)
      field(:reasoning, :string)
    end

    output do
      field(:status, :string)
      field(:processed_at, :string)
    end
  end

  outcomes do
    outcome(:complete, to: nil)
  end

  def handle_task(input) do
    # Ban the user from the platform
    {:user_banned,
     %{
       status: "Content filtered: #{input.reasoning}",
       processed_at: DateTime.utc_now() |> to_string()
     }}
  end
end
