## Unreleased

## 0.4.10 [2025-09-11]
- Add support for `elementMap()` traversal step via `Gremlex.Graph.element_map/1` and `Gremlex.Graph.element_map/2` functions

## 0.4.9 [2025-09-11]
- Handle multiple pong messages in a query response.

## 0.4.8 [2025-09-10]
- Handle server errors in query response.

## 0.4.7 [2025-09-08]

## Fixes
- Fix unexpected :ok in query response

## 0.4.6 [2025-07-14]

### Fixes
- Fix wrong deserialization in response with multiple `text` blocks

## 0.4.5 [2025-07-14] (BROKEN!)

### Added
- Add `with` configuration, as `with_` function, to graph traversal

### Fixes
- Properly handle `:pong` response for long-lived requests
- Support for multiple responses blocks in a single websocket response

## 0.4.4 [2025-06-12]

### Added
- function `Gremlex.Graph.neq/2` similar to `Gremlex.Graph.eq/2`

## 0.4.3 [2025-06-05]

### Fixes
- Increase default timeout from 5s to 30s to match Gremlin's default `evaluationTimeout`

## 0.4.2 [2025-05-19]

### Added
- function `Gremlex.Graph.gte/2` similar to `Gremlex.Graph.gt/2`

## 0.4.1 [2025-04-16]

### Fixes
- `@spec` in `Gremlex.Graph.by/2` and `Gremlex.Graph.by/3`

## 0.4.0

### Added
- `Gremlex.Graph.side_effect/2`
- `Gremlex.Graph.emit/1`
- Multiple edge ids in `Gremlex.Graph.e/2`

### Breaking changes
- Replaced websocket library with `Mint.Websocket`
- Removed `confex` style configuration
