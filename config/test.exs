import Config

config :gremlex,
  host: System.get_env("GREMLEX_HOST", "127.0.0.1"),
  port: 8182,
  path: "/gremlin",
  pool_size: 10,
  overflow: 10,
  secure: false

config :logger, level: :warning
