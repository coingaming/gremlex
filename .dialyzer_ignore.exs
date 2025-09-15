# .dialyzer_ignore.exs
[
  # Mint.WebSocket.recv/3 returns error tuples of 4 elements, here: https://hexdocs.pm/mint_web_socket/1.0.4/Mint.WebSocket.html#recv/3
  # but dialyzer is not able to infer that, hence ignoring the pattern match warning
  {"lib/gremlex/client.ex", :pattern_match, 154},
]
