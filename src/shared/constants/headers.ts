export const GALYARDER_ROUTE_RESPONSE_HEADERS = {
  cache: "X-Galyarder-Route-Cache",
  cacheHit: "X-Galyarder-Route-Cache-Hit",
  latencyMs: "X-Galyarder-Route-Latency-Ms",
  model: "X-Galyarder-Route-Model",
  progress: "X-Galyarder-Route-Progress",
  provider: "X-Galyarder-Route-Provider",
  responseCost: "X-Galyarder-Route-Response-Cost",
  tokensIn: "X-Galyarder-Route-Tokens-In",
  tokensOut: "X-Galyarder-Route-Tokens-Out",
} as const;
