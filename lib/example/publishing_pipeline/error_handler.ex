defmodule Example.ErrorHandler do
  use Hive.Agent

  schema do
    input do
      field :reason, :any, required: true
    end

    output do
      field :error_id, :string
      field :status, :string
    end
  end

  outcomes do
    outcome :handled, to: nil  # End of error handling
  end

  def handle_task(input) do
    error_id = log_error(input)

    {:handled, %{
      error_id: error_id,
      status: "error_logged"
    }}
  end

  defp log_error(error) do
    # Simulate error logging
    # In reality, this could write to a logging service, notify admins, etc.
    error_id = "err_#{:crypto.strong_rand_bytes(8) |> Base.url_encode64}"
    IO.puts("Error logged: #{error_id} - #{inspect(error)}")
    error_id
  end
end
