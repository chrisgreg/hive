import Config

config :hive,
  log_level: :info,
  default_retry_attempts: 3,
  retry_backoff: :exponential,
  instructor: [
    openai: [
      api_key: System.get_env("OPENAI_API_KEY"),
      adapter: Instructor.Adapters.OpenAI
    ]
  ]
