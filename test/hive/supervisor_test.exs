defmodule Hive.SupervisorTest do
  use ExUnit.Case, async: false

  setup do
    Application.ensure_all_started(:hive)
    on_exit(fn -> Application.stop(:hive) end)
    :ok
  end

  defmodule TestAgent do
    use Hive.Agent

    input do
      field(:name, :string, required: true)
    end

    output do
      field(:message, :string)
    end

    outcomes do
      outcome(:success, to: nil)
    end

    def handle_task(input) do
      # Simulate some work
      Process.sleep(100)
      {:success, %{message: "Hello, #{input.name}!"}}
    end
  end

  test "multiple pipelines can run simultaneously" do
    task1 = Task.async(fn -> TestAgent.process(%{name: "Alice"}) end)
    task2 = Task.async(fn -> TestAgent.process(%{name: "Bob"}) end)
    task3 = Task.async(fn -> TestAgent.process(%{name: "Charlie"}) end)

    results = [Task.await(task1), Task.await(task2), Task.await(task3)]

    assert Enum.all?(results, fn
             {:success, %{message: msg}} -> String.starts_with?(msg, "Hello")
             _ -> false
           end)
  end

  test "supervisor handles concurrent pipeline execution" do
    # Start multiple pipelines concurrently
    tasks =
      for name <- ["Alice", "Bob", "Charlie", "Dave", "Eve"] do
        Task.async(fn -> TestAgent.process(%{name: name}) end)
      end

    # Wait for all tasks to complete
    results = Task.await_many(tasks)

    # Verify all pipelines completed successfully
    assert Enum.all?(results, fn
             {:success, %{message: msg}} -> String.starts_with?(msg, "Hello")
             _ -> false
           end)

    # Verify each result is unique
    messages = Enum.map(results, fn {:success, %{message: msg}} -> msg end)
    assert length(Enum.uniq(messages)) == length(messages)
  end
end
