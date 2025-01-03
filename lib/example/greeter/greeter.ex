defmodule Example.Greeter do
  use Hive.Agent

  schema do
    input do
      field(:name, :string, required: true)
      field(:language, :string, default: "en")
    end

    output do
      field(:greeting, :string)
      field(:timestamp, :string)
    end
  end

  outcomes do
    outcome(:success, to: Example.Formatter)
    outcome(:error, to: nil)
  end

  def handle_task(input) do
    greeting =
      case input.language do
        "es" -> "¡Hola"
        "fr" -> "Bonjour"
        _ -> "Hello"
      end

    {:success,
     %{
       greeting: "#{greeting} #{input.name}",
       timestamp: DateTime.utc_now() |> to_string()
     }}
  end
end

defmodule Example.Formatter do
  use Hive.Agent

  schema do
    input do
      field(:greeting, :string, required: true)
      field(:timestamp, :string, required: true)
    end

    output do
      field(:formatted_message, :string)
      field(:metadata, :map)
    end
  end

  outcomes do
    outcome(:complete, to: nil)
  end

  def handle_task(input) do
    {:complete,
     %{
       formatted_message: String.upcase(input.greeting),
       metadata: %{
         processed_at: input.timestamp,
         formatter_version: "1.0"
       }
     }}
  end
end
