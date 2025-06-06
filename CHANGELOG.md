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
