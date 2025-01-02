defmodule Example.Publisher do
  use Hive.Agent

  schema do
    input do
      field(:content, :string, required: true)
      field(:metadata, :map, required: true)
      field(:refinements, :map, required: true)
    end

    output do
      field(:url, :string)
      field(:published_at, :datetime)
      field(:status, :string)
    end
  end

  outcomes do
    # End of pipeline
    outcome(:published, to: nil)
    outcome(:retry, to: __MODULE__, max_attempts: 3)
    outcome(:error, to: Example.ErrorHandler)
  end

  def handle_task(input) do
    case publish_content(input) do
      {:ok, url} ->
        {:published,
         %{
           url: url,
           published_at: DateTime.utc_now(),
           status: "published"
         }}

      {:error, :service_unavailable} ->
        {:retry, input}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp publish_content(%{content: _content, metadata: _metadata}) do
    # Simulate publishing to a content management system
    # In reality, this could be a CMS API call, database write, etc.
    if :rand.uniform() > 0.1 do
      url = "https://example.com/content/#{:crypto.strong_rand_bytes(8) |> Base.url_encode64()}"
      {:ok, url}
    else
      {:error, :service_unavailable}
    end
  end
end
