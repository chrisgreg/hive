defmodule Example.ContentFilterIdentifier do
  use Hive.Agent

  schema do
    input do
      field(
        :content,
        :string,
        "The user's content to be checked for rudeness or offensive material"
      )
    end

    output do
      field(:spam?, :boolean, "Whether the content was identified as spam/offensive")
      field(:reasoning, :string, "Explanation for why the content was marked as spam or allowed")
    end
  end

  outcomes do
    outcome(:filter,
      to: Example.ContentFilterIdentifier.Filter,
      description: "Choose when content is offensive, rude, or violates community guidelines"
    )

    outcome(:pass,
      to: Example.ContentFilterIdentifier.Pass,
      description: "Choose when content is appropriate and can be published"
    )

    outcome(:retry,
      to: __MODULE__,
      max_attempts: 3,
      description: "Choose when the decision is unclear and needs another review"
    )

    outcome(:error,
      to: Example.ErrorHandler,
      description: "Choose when there's a critical issue that needs human review"
    )
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
      field(:content, :string, "The approved content to be published")
    end

    output do
      field(:status, :string, "The final status of the approved content")
      field(:processed_at, :string, "When the content was processed")
    end
  end

  outcomes do
    outcome(:complete,
      to: nil,
      description: "Final state after content has been approved and stored"
    )
  end

  def handle_task(input) do
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
      field(:spam?, :boolean, "Whether the content was flagged as spam")
      field(:reasoning, :string, "The explanation for why the content was filtered")
    end

    output do
      field(:status, :string, "The final status of the filtered content")
      field(:processed_at, :string, "When the content was processed")
    end
  end

  outcomes do
    outcome(:complete,
      to: nil,
      description: "Final state after content has been filtered and user banned"
    )
  end

  def handle_task(input) do
    {:user_banned,
     %{
       status: "Content filtered: #{input.reasoning}",
       processed_at: DateTime.utc_now() |> to_string()
     }}
  end
end
