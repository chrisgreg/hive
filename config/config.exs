import Config

config :hive, :content_pipeline,
  agents: [
    Example.ContentGenerator,
    Example.DuplicateChecker,
    Example.ContentRefiner,
    Example.Publisher,
    Example.ErrorHandler
  ]

config :logger, :console, level: :debug
