import assert from "node:assert/strict";
import test from "node:test";

import {
  DEFAULT_GALYARDER_ROUTE_BASE_URL,
  resolveGalyarderRouteBaseUrl,
} from "../../src/shared/utils/resolveGalyarderRouteBaseUrl.ts";

test("resolveGalyarderRouteBaseUrl prefers GALYARDER_ROUTE_BASE_URL", () => {
  assert.equal(
    resolveGalyarderRouteBaseUrl({
      GALYARDER_ROUTE_BASE_URL: "https://internal.example.com/",
      BASE_URL: "https://base.example.com",
      NEXT_PUBLIC_BASE_URL: "https://public.example.com",
    }),
    "https://internal.example.com"
  );
});

test("resolveGalyarderRouteBaseUrl falls back to BASE_URL", () => {
  assert.equal(
    resolveGalyarderRouteBaseUrl({
      BASE_URL: "https://base.example.com/",
      NEXT_PUBLIC_BASE_URL: "https://public.example.com",
    }),
    "https://base.example.com"
  );
});

test("resolveGalyarderRouteBaseUrl falls back to NEXT_PUBLIC_BASE_URL", () => {
  assert.equal(
    resolveGalyarderRouteBaseUrl({
      NEXT_PUBLIC_BASE_URL: "https://public.example.com/",
    }),
    "https://public.example.com"
  );
});

test("resolveGalyarderRouteBaseUrl ignores blank values", () => {
  assert.equal(
    resolveGalyarderRouteBaseUrl({
      GALYARDER_ROUTE_BASE_URL: "   ",
      BASE_URL: "",
      NEXT_PUBLIC_BASE_URL: " https://public.example.com/ ",
    }),
    "https://public.example.com"
  );
});

test("resolveGalyarderRouteBaseUrl uses the default localhost fallback", () => {
  assert.equal(resolveGalyarderRouteBaseUrl({}), DEFAULT_GALYARDER_ROUTE_BASE_URL);
});
