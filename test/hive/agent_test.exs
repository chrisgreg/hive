defmodule Hive.AgentTest do
  use ExUnit.Case, async: true
  doctest Hive.Agent

  setup do
    Application.ensure_all_started(:hive)
    on_exit(fn -> Application.stop(:hive) end)
    :ok
  end

  # Test Agent Implementation
  defmodule TestAgent do
    use Hive.Agent

    input do
      field(:name, :string, required: true)
      field(:age, :integer, default: 0)
    end

    output do
      field(:message, :string)
      field(:processed_at, :string)
    end

    outcomes do
      outcome(:success, to: nil)
      outcome(:retry, max_attempts: 3)
      outcome(:error, to: nil)
    end

    def handle_task(input) do
      case input do
        %{name: name} ->
          age = Map.get(input, :age, 0)
          retry_attempt = Map.get(input, :_retry_attempt, 0)

          cond do
            name == "retry_me" and retry_attempt < 2 ->
              {:retry,
               Map.merge(input, %{
                 message: "Retrying...",
                 processed_at: DateTime.utc_now() |> to_string()
               })}

            name == "retry_me" and retry_attempt >= 2 ->
              {:success,
               Map.merge(input, %{
                 message: "Retry successful",
                 processed_at: DateTime.utc_now() |> to_string()
               })}

            name == "error_case" ->
              {:error,
               Map.merge(input, %{
                 message: "Error occurred",
                 processed_at: DateTime.utc_now() |> to_string()
               })}

            true ->
              {:success,
               Map.merge(input, %{
                 message: "Hello #{name}, you are #{age} years old",
                 processed_at: DateTime.utc_now() |> to_string()
               })}
          end

        _ ->
          {:error, %{message: "name is required"}}
      end
    end
  end

  describe "schema validation" do
    test "validates input schema with valid data" do
      result = TestAgent.process(%{name: "Alice", age: 25})
      assert {:success, %{message: "Hello Alice, you are 25 years old"}} = result
    end

    test "validates input schema with missing required field" do
      assert {:error, %{message: reason}} = TestAgent.process(%{age: 25})
      assert reason == "name is required"
    end

    test "uses default value for optional field" do
      result = TestAgent.process(%{name: "Bob"})
      assert {:success, %{message: "Hello Bob, you are 0 years old"}} = result
    end
  end

  describe "outcome routing" do
    test "handles success outcome" do
      result = TestAgent.process(%{name: "Carol", age: 30})
      assert {:success, data} = result
      assert data.message == "Hello Carol, you are 30 years old"
      assert String.match?(data.processed_at, ~r/\d{4}-\d{2}-\d{2}/)
    end

    test "handles error outcome" do
      result = TestAgent.process(%{name: "error_case", age: 30})
      assert {:error, data} = result
      assert data.message == "Error occurred"
    end
  end

  describe "retry mechanism" do
    test "handles retry with max attempts" do
      result = TestAgent.process(%{name: "retry_me", age: 30})
      assert {:success, data} = result
      assert data.message == "Retry successful"
    end
  end

  describe "pipeline tracking" do
    test "maintains pipeline ID throughout processing" do
      pipeline_id = "test_pipeline_123"
      result = TestAgent.process(%{name: "Dave", age: 35, _pipeline_id: pipeline_id})
      assert {:success, data} = result
      assert data._pipeline_id == pipeline_id
    end

    test "generates pipeline ID if not provided" do
      result = TestAgent.process(%{name: "Eve", age: 40})
      assert {:success, data} = result
      assert is_integer(data._pipeline_id)
    end
  end

  describe "agent routing" do
    defmodule RouterTestAgent do
      use Hive.Agent

      input do
        field(:message, :string, required: true)
      end

      output do
        field(:processed_message, :string)
      end

      outcomes do
        outcome(:next, to: RouterTestAgent.Next)
        outcome(:error, to: RouterTestAgent.Error)
      end

      def handle_task(input) do
        case input.message do
          "error" -> {:error, %{processed_message: "Error occurred"}}
          _ -> {:next, %{processed_message: "Processed: #{input.message}"}}
        end
      end
    end

    defmodule RouterTestAgent.Next do
      use Hive.Agent

      input do
        field(:processed_message, :string, required: true)
      end

      output do
        field(:final_message, :string)
      end

      outcomes do
        outcome(:complete, to: nil)
      end

      def handle_task(input) do
        {:complete, %{final_message: "Final: #{input.processed_message}"}}
      end
    end

    defmodule RouterTestAgent.Error do
      use Hive.Agent

      input do
        field(:processed_message, :string, required: true)
      end

      output do
        field(:error_message, :string)
      end

      outcomes do
        outcome(:complete, to: nil)
      end

      def handle_task(input) do
        {:complete, %{error_message: "Error handled: #{input.processed_message}"}}
      end
    end

    test "successfully routes to next agent" do
      result = RouterTestAgent.process(%{message: "hello"})
      assert {:complete, %{final_message: "Final: Processed: hello"}} = result
    end

    test "successfully routes to error handler" do
      result = RouterTestAgent.process(%{message: "error"})
      assert {:complete, %{error_message: "Error handled: Error occurred"}} = result
    end

    test "maintains pipeline ID through routing chain" do
      pipeline_id = "test_pipeline_456"
      result = RouterTestAgent.process(%{message: "hello", _pipeline_id: pipeline_id})
      assert {:complete, data} = result
      assert data._pipeline_id == pipeline_id
    end
  end
end
