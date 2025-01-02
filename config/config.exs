import Config

config :hive,
  log_level: :debug,
  default_retry_attempts: 3,
  retry_backoff: :exponential
