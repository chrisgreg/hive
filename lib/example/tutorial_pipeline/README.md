# Tutorial Generation Pipeline

This example demonstrates a sophisticated AI-powered tutorial generation pipeline with intelligent caching using the Hive framework.

## Pipeline Overview

The pipeline consists of 5 main agents:

1. **TutorialRequestValidator** - Validates input parameters and generates cache keys
2. **TutorialCacheChecker** - Checks ETS for existing tutorials to avoid regeneration
3. **TutorialGenerator** - Uses OpenAI to generate tutorial content
4. **TutorialQualityValidator** - Uses AI to assess tutorial quality with LLM routing
5. **TutorialCacheWriter** - Stores approved tutorials in ETS for future use

## Features

### AI Integration

- **Tutorial Generation**: Uses GPT-4 to create comprehensive, structured tutorials
- **Quality Validation**: AI-powered quality assessment with automatic routing decisions
- **Intelligent Routing**: The quality validator uses LLM routing to decide if content should be approved, revised, or rejected

### Caching Strategy

- **ETS Storage**: Fast in-memory caching of generated tutorials
- **Smart Cache Keys**: Normalized keys based on topic, difficulty, and length
- **Cache-First Approach**: Always checks cache before generating new content

### Error Handling

- **Retry Logic**: Automatic retries for AI generation failures
- **Validation**: Input validation and quality checks at multiple stages
- **Graceful Degradation**: Comprehensive error handling throughout the pipeline

## Usage

```elixir
# Generate a new tutorial
{:cached, result} = Examples.run_tutorial_generator(
  "How to make sourdough bread",
  "intermediate",
  2000
)

# Access the generated content
IO.puts(result.tutorial_content)

# Second call returns cached result instantly
{:cache_hit, cached} = Examples.run_tutorial_generator(
  "How to make sourdough bread",
  "intermediate",
  2000
)

# Clear cache if needed
Examples.clear_tutorial_cache()
```

## Pipeline Flow

1. **Request Validation**

   - Validates topic (min 5 chars)
   - Validates difficulty (beginner/intermediate/advanced)
   - Validates max_length (100-5000 words)
   - Generates normalized cache key

2. **Cache Check**

   - Looks up tutorial in ETS using cache key
   - Returns immediately if found (cache hit)
   - Continues to generation if not found (cache miss)

3. **AI Generation**

   - Builds detailed prompt based on requirements
   - Calls OpenAI API to generate tutorial
   - Extracts metadata (sections, key points, word count)
   - Retries up to 3 times on failure

4. **Quality Validation**

   - Basic checks (word count, minimum length)
   - AI assessment using LLM routing:
     - `approved`: Content meets standards
     - `needs_revision`: Minor issues, regenerate
     - `rejected`: Major issues, fail pipeline

5. **Cache Storage**
   - Stores tutorial with metadata in ETS
   - Adds timestamp for cache management
   - Returns final result to user

## Configuration

The pipeline uses these configurations:

- **AI Model**: GPT-4o-mini for both generation and validation
- **Cache Table**: Named ETS table `:tutorial_cache`
- **Retry Attempts**: 3 for generation, built-in retries for AI calls
- **Word Limits**: 100 minimum, 5000 maximum

## Example Output Structure

```elixir
%{
  topic: "How to make sourdough bread",
  difficulty: "intermediate",
  tutorial_content: "# How to Make Sourdough Bread\n\n## Introduction\n...",
  metadata: %{
    word_count: 1847,
    sections: ["Introduction", "Prerequisites", "Ingredients", ...],
    key_points: ["Patience is key", "Temperature matters", ...],
    generated_at: "2024-01-15 10:30:00",
    cached_at: "2024-01-15 10:30:15",
    quality_assessment: %{
      word_count_ok: true,
      actual_word_count: 1847
    }
  },
  cache_key: "tutorial:how_to_make_sourdough_bread:intermediate:2000",
  cached_at: "2024-01-15 10:30:15"
}
```

## Benefits

1. **Performance**: Cached tutorials return instantly
2. **Cost Efficiency**: Reduces AI API calls through caching
3. **Quality Assurance**: AI validates content before caching
4. **Flexibility**: Easy to extend with additional validation rules
5. **Reliability**: Automatic retries and comprehensive error handling
