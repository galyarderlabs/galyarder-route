import test from "node:test";
import assert from "node:assert/strict";

import {
  buildGalyarderRouteResponseMetaHeaders,
  buildGalyarderRouteSseMetadataComment,
  formatGalyarderRouteCost,
  getGalyarderRouteTokenCounts,
} from "../../src/domain/galyarderRouteResponseMeta.ts";

test("getGalyarderRouteTokenCounts normalizes common usage shapes", () => {
  assert.deepEqual(
    getGalyarderRouteTokenCounts({
      prompt_tokens: 12,
      completion_tokens: 5,
    }),
    { input: 12, output: 5 }
  );
  assert.deepEqual(
    getGalyarderRouteTokenCounts({
      input_tokens: "9",
      output_tokens: "4",
    }),
    { input: 9, output: 4 }
  );
});

test("buildGalyarderRouteResponseMetaHeaders formats provider alias, tokens, latency, and cost", () => {
  const headers = buildGalyarderRouteResponseMetaHeaders({
    provider: "claude",
    model: "claude-sonnet-4-6",
    cacheHit: true,
    latencyMs: 1234.6,
    usage: {
      prompt_tokens: 11,
      completion_tokens: 7,
    },
    costUsd: 0.00123456789,
  });

  assert.equal(headers["X-Galyarder-Route-Provider"], "cc");
  assert.equal(headers["X-Galyarder-Route-Model"], "claude-sonnet-4-6");
  assert.equal(headers["X-Galyarder-Route-Cache-Hit"], "true");
  assert.equal(headers["X-Galyarder-Route-Latency-Ms"], "1235");
  assert.equal(headers["X-Galyarder-Route-Tokens-In"], "11");
  assert.equal(headers["X-Galyarder-Route-Tokens-Out"], "7");
  assert.equal(headers["X-Galyarder-Route-Response-Cost"], "0.0012345679");
});

test("buildGalyarderRouteSseMetadataComment emits comment lines compatible with SSE", () => {
  const comment = buildGalyarderRouteSseMetadataComment({
    provider: "openai",
    model: "gpt-4o-mini",
    usage: {
      prompt_tokens: 4,
      completion_tokens: 2,
    },
    latencyMs: 50,
    costUsd: formatGalyarderRouteCost(0),
  });

  assert.match(comment, /^: x-galyarder-route-cache-hit=false/m);
  assert.match(comment, /^: x-galyarder-route-provider=openai/m);
  assert.match(comment, /^: x-galyarder-route-model=gpt-4o-mini/m);
  assert.match(comment, /^: x-galyarder-route-tokens-in=4/m);
  assert.match(comment, /^: x-galyarder-route-tokens-out=2/m);
  assert.match(comment, /^: x-galyarder-route-response-cost=0\.0000000000/m);
});
