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
      Assess if the content is deemed as either offensive or not.

      Provide a succinct reasoning for your decision.

      If the content is offensive, the user will be banned - in your reasoning, address the user and the reason for the ban.
      If the content is not offensive, the user will be allowed to post - in your reasoning, address the user and the reason for the allowed post.

      Swearing is allowed, but only if it's to emphasize a point.
      """
    ]
  end

  def handle_task(input) do
    # Return a default outcome with properly structured output data
    # The framework's LLM routing will override this if needed
    {:pass,
     %{
       content: input.content,
       spam?: false,
       reasoning: "Pending LLM evaluation"
     }}
  end
end

defmodule Example.ContentFilterIdentifier.Pass do
  use Hive.Agent

  schema do
    input do
      field(:content, :string, "The approved content to be published")
      field(:spam?, :boolean, "Whether the content was flagged as spam")
      field(:reasoning, :string, "The explanation for why the content was allowed")
      field(:llm_reasoning, :string, "The LLM's reasoning for the decision")
    end

    output do
      field(:status, :string, "The final status of the approved content")
      field(:processed_at, :string, "When the content was processed")
      field(:reasoning, :string, "The reason for approval")
    end
  end

  outcomes do
    outcome(:complete,
      to: nil,
      description: "Final state after content has been approved and stored"
    )
  end

  def handle_task(input) do
    # Use LLM reasoning if available
    reasoning = input[:llm_reasoning] || input[:reasoning] || "Content approved"

    {:comment_valid,
     %{
       status: "Content approved",
       reasoning: reasoning,
       processed_at: DateTime.utc_now() |> to_string()
     }}
  end
end

defmodule Example.ContentFilterIdentifier.Filter do
  use Hive.Agent

  schema do
    input do
      field(:content, :string, "The content that was filtered")
      field(:spam?, :boolean, "Whether the content was flagged as spam")
      field(:reasoning, :string, "The explanation for why the content was filtered")
      field(:llm_reasoning, :string, "The LLM's reasoning for the decision")
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
    # Use LLM reasoning if available, otherwise fall back to regular reasoning
    reasoning = input[:llm_reasoning] || input[:reasoning] || "Content violated guidelines"

    {:user_banned,
     %{
       status: "Content filtered: #{reasoning}",
       processed_at: DateTime.utc_now() |> to_string()
     }}
  end
end
