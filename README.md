# 🐝 Hive

Hive is an Elixir framework for building autonomous agent pipelines with built-in validation,
routing, and error handling. It provides a structured way to create interconnected agents
that can process data, make decisions, and handle errors gracefully.

## Features

- 🔄 **Pipeline-based Processing**: Chain multiple agents together to create complex workflows
- ✅ **Built-in Validation**: Schema-based input/output validation for each agent
- 🔁 **Automatic Retry Handling**: Configurable retry mechanisms for failed operations
- 📝 **Comprehensive Logging**: Debug logging of pipeline execution flow
- 🔍 **Pipeline Tracking**: Unique IDs for tracking requests through the entire pipeline
- ⚡ **GenServer-based**: Ready for distributed processing

## Installation

Add `hive` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:hive, "~> 0.1.0"}
  ]
end
```

## Simple Example

Here's a basic example of how to use Hive to create a simple agent:

```elixir
defmodule MyApp.SimpleGreeter do
  use Hive.Agent

  input do
    field :name, :string, required: true
  end

  output do
    field :greeting, :string
  end

  outcomes do
    outcome :success, to: nil
  end

  def handle_task(input) do
    greeting = "Hello, #{input.name}!"
    {:success, %{greeting: greeting}}
  end
end

# Usage
result = MyApp.SimpleGreeter.process(%{name: "Alice"})
case result do
  {:success, data} -> IO.puts(data.greeting)  # Outputs: Hello, Alice!
  {:error, reason} -> IO.puts("Error: #{inspect(reason)}")
end
```

This example demonstrates:

1. Defining input and output schemas
2. Specifying a simple outcome
3. Implementing the `handle_task/1` function
4. Processing input and handling the result

## Quick Start

For more advanced usage, let's walk through creating a multi-agent pipeline:

### 1. Define Your First Agent

```elixir
defmodule MyApp.ContentGenerator do
  use Hive.Agent

  input do
    field :prompt, :string, required: true
    field :max_tokens, :integer, default: 1000
  end

  output do
    field :content, :string
    field :metadata, :map
  end

  outcomes do
    outcome :success, to: MyApp.ContentRefiner
    outcome :error, to: MyApp.ErrorHandler
    outcome :retry, max_attempts: 3
  end

  def handle_task(input) do
    case generate_content(input) do
      {:ok, content} ->
        {:success, %{
          content: content,
          metadata: %{generated_at: DateTime.utc_now()}
        }}
      {:error, _reason} ->
        {:retry, %{}}
    end
  end

  defp generate_content(input) do
    # Your content generation logic here
    {:ok, "Generated content for: #{input.prompt}"}
  end
end
```

### 2. Create a Pipeline

Connect multiple agents to form a processing pipeline:

```elixir
defmodule MyApp.Pipeline do
  # First Agent: Generates content
  defmodule ContentGenerator do
    use Hive.Agent
    # ... (as shown above)
  end

  # Second Agent: Refines the content
  defmodule ContentRefiner do
    use Hive.Agent

    input do
      field :content, :string
      field :metadata, :map
    end

    output do
      field :content, :string
      field :metadata, :map
    end

    outcomes do
      outcome :success, to: MyApp.Publisher
      outcome :error, to: MyApp.ErrorHandler
    end

    def handle_task(input) do
      {:success, %{
        content: refine_content(input.content),
        metadata: Map.put(input.metadata, :refined_at, DateTime.utc_now())
      }}
    end
  end

  # Final Agent: Publishes the content
  defmodule Publisher do
    use Hive.Agent

    input do
      field :content, :string
      field :metadata, :map
    end

    output do
      field :url, :string
      field :published_at, :datetime
    end

    outcomes do
      outcome :success, to: nil  # End of pipeline
      outcome :error, to: MyApp.ErrorHandler
    end

    def handle_task(input) do
      {:success, %{
        url: publish_content(input.content),
        published_at: DateTime.utc_now()
      }}
    end
  end
end
```

### 3. Execute the Pipeline

```elixir
# Start the pipeline with initial input
result = Example.ContentGenerator.process(%{topic: "Elixir", length: 500, style: "smart"})

case result do
  {:published, data} -> IO.puts "Published at: #{data.url}"
  {:retry, reason} -> IO.puts "Error: #{inspect(reason)}"
end
```

## LLM Routing Example

Hive supports LLM-based routing, allowing you to use language models to make dynamic decisions in your agent pipelines. Here's an example of how to implement LLM routing:

```elixir
defmodule MyApp.ContentFilterIdentifier do
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
    outcome(:filter, to: MyApp.ContentFilterIdentifier.Filter)
    outcome(:pass, to: MyApp.ContentFilterIdentifier.Pass)
    outcome(:retry, to: __MODULE__, max_attempts: 3)
    outcome(:error, to: MyApp.ErrorHandler)
  end

  llm_routing do
    [
      model: "gpt-4-turbo",
      prompt: """
      Assess if the content is spam or offensive.
      Provide a succinct reasoning for your decision.

      If the content is spam or offensive, it will be filtered.
      """
    ]
  end

  def handle_task(input) do
    case Hive.LLM.Router.determine_outcome(__MODULE__, :initial, input) do
      {:ok, :filter, data} ->
        {:filter, %{spam?: true, reasoning: data.llm_reasoning}}

      {:ok, :pass, data} ->
        {:pass, %{spam?: false, reasoning: data.llm_reasoning, content: input.content}}

      {:error, reason} ->
        {:error, %{reason: reason}}
    end
  end
end
```

In this example:

1. We define an agent `ContentFilterIdentifier` that uses LLM routing to determine if content should be filtered or passed.
2. The `llm_routing` macro is used to configure the LLM model and provide a custom prompt.
3. In `handle_task/1`, we use `Hive.LLM.Router.determine_outcome/3` to get the LLM's decision.
4. Based on the LLM's decision, we route the content to either the `Filter` or `Pass` outcome.

### Integration with Instructor

Hive uses [Instructor](https://github.com/instructor-ai/instructor-elixir) under the hood for structured LLM outputs. The `Hive.LLM.Router` automatically creates an Instructor-compatible schema for the LLM's decision:

```elixir
defmodule Hive.LLM.Router.Decision do
  use Ecto.Schema
  use Instructor.Validator

  @primary_key false
  embedded_schema do
    field(:outcome, :string)
    field(:reasoning, :string)
    field(:next_step, :string)
  end
end
```

### Automatic Schema Translation

Hive automatically translates your agent's schema definitions into Instructor-compatible schemas. For example, your input/output schemas:

```elixir
schema do
  input do
    field(:content, :string, required: true)
  end

  output do
    field(:spam?, :boolean)
    field(:reasoning, :string)
  end
end
```

Are automatically translated to Instructor schemas behind the scenes, ensuring type safety and validation when working with LLM responses. This translation handles various field types including:

- Basic types (:string, :integer, :float, :boolean)
- Complex types (:map, {:array, type})
- Nested schemas
- Required/optional fields

This approach allows for dynamic, content-aware decision making within your Hive pipelines, leveraging the power of large language models while maintaining type safety and validation.

## Configuration Options

Configure Hive in your `config/config.exs`:

### Logging Levels

- `:debug` - Detailed pipeline execution flow, useful for development
- `:info` - General pipeline progress
- `:warning` - Retry attempts and potential issues
- `:error` - Failed operations and error states

### Retry Behavior

The retry delay is calculated based on the `retry_backoff` setting:

- `:linear` - Delay = attempt_number \* 1000ms

  - Attempt 1: 1 second
  - Attempt 2: 2 seconds
  - Attempt 3: 3 seconds

- `:exponential` - Delay = (2 ^ (attempt_number - 1)) \* 1000ms
  - Attempt 1: 1 second
  - Attempt 2: 2 seconds
  - Attempt 3: 4 seconds
  - Attempt 4: 8 seconds

### Retry Configuration

Configure retry behavior for transient failures:

```elixir
outcomes do
  outcome :retry, max_attempts: 3  # Will retry up to 3 times
end
```

### Custom Error Handling

Create specialized error handlers:

```elixir
defmodule MyApp.ErrorHandler do
  use Hive.Agent

  input do
    field :error, :any
    field :metadata, :map
  end

  outcomes do
    outcome :handled, to: nil
  end

  def handle_task(input) do
    # Log error, send notifications, etc.
    {:handled, %{status: :error_logged}}
  end
end
```

### Pipeline Tracking

Track requests through the pipeline using the automatically generated pipeline ID:

```elixir
def handle_task(%{_pipeline_id: pipeline_id} = input) do
  Logger.metadata(pipeline_id: pipeline_id)
  # Your processing logic here
end
```

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b feature/my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin feature/my-new-feature`)
5. Create new Pull Request

## License

This project is licensed under the MIT License - see the LICENSE.md file for details.
