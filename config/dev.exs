import Config

config :gremlex,
  host: "127.0.0.1",
  port: 8182,
  path: "/gremlin",
  pool_size: 1,
  overflow: 10,
  secure: false
