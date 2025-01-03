defmodule Example.Greeter do
  use Hive.Agent

  schema do
    input do
      field(:language, :string, required: true)
      field(:name, :string, required: true)
    end

    output do
      field(:greeting, :string)
      field(:timestamp, :string)
    end
  end

  outcomes do
    outcome(:supported_language, to: Example.Greeter.Formatter)
    outcome(:unsupported_language, to: Example.Greeter.UnsupportedLanguage)
  end

  def handle_task(input) do
    {result, greeting} =
      case input.language do
        "es" -> {:supported_language, "¡Hola"}
        "fr" -> {:supported_language, "Bonjour"}
        _ -> {:unsupported_language, :error}
      end

    {result,
     %{
       greeting: "#{greeting} #{input.name}",
       language: input.language,
       timestamp: DateTime.utc_now() |> to_string()
     }}
  end
end

defmodule Example.Greeter.Formatter do
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
         greeter_formatter_version: "1.0"
       }
     }}
  end
end

defmodule Example.Greeter.UnsupportedLanguage do
  use Hive.Agent

  schema do
    input do
      field(:language, :string, required: true)
    end

    output do
      field(:unsupported_language, :string)
    end

    outcomes do
      outcome(:unsupported_language, to: nil)
    end
  end

  def handle_task(input) do
    {:unsupported_language,
     %{
       unsupported_language: input.language
     }}
  end
end
