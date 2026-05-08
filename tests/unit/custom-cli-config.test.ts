import test from "node:test";
import assert from "node:assert/strict";

import {
  buildAliasEnvVar,
  buildCustomCliEnvScript,
  buildCustomCliJsonConfig,
  normalizeOpenAiBaseUrl,
} from "../../src/app/(dashboard)/dashboard/cli-tools/components/customCliConfig.ts";

test("normalizeOpenAiBaseUrl appends /v1 only when needed", () => {
  assert.equal(normalizeOpenAiBaseUrl("http://localhost:20128"), "http://localhost:20128/v1");
  assert.equal(
    normalizeOpenAiBaseUrl("https://example.com/proxy/v1"),
    "https://example.com/proxy/v1"
  );
});

test("buildAliasEnvVar sanitizes aliases for env variable export", () => {
  assert.equal(buildAliasEnvVar("review"), "GALYARDER_ROUTE_MODEL_REVIEW");
  assert.equal(buildAliasEnvVar("plan mode"), "GALYARDER_ROUTE_MODEL_PLAN_MODE");
  assert.equal(buildAliasEnvVar(""), null);
});

test("custom CLI generators include default model and alias mappings", () => {
  const envScript = buildCustomCliEnvScript({
    cliName: "My Team CLI",
    baseUrl: "http://localhost:20128",
    apiKey: "sk_test_123",
    defaultModel: "galyarder-route/fast",
    aliasMappings: [
      { alias: "review", model: "cc/claude-sonnet-4-5-20250929" },
      { alias: "vision", model: "gemini/gemini-3-flash" },
    ],
  });

  assert.match(envScript, /export OPENAI_BASE_URL="http:\/\/localhost:20128\/v1"/);
  assert.match(envScript, /export OPENAI_MODEL="galyarder-route\/fast"/);
  assert.match(envScript, /export GALYARDER_ROUTE_MODEL_REVIEW="cc\/claude-sonnet-4-5-20250929"/);
  assert.match(envScript, /# http:\/\/localhost:20128\/v1\/chat\/completions/);
  assert.match(envScript, /my-team-cli --base-url "\$OPENAI_BASE_URL"/);

  const jsonConfig = JSON.parse(
    buildCustomCliJsonConfig({
      cliName: "My Team CLI",
      baseUrl: "http://localhost:20128",
      apiKey: "sk_test_123",
      defaultModel: "galyarder-route/fast",
      aliasMappings: [{ alias: "review", model: "cc/claude-sonnet-4-5-20250929" }],
    })
  );

  assert.deepEqual(jsonConfig, {
    name: "My Team CLI",
    provider: {
      type: "openai",
      baseURL: "http://localhost:20128/v1",
      apiKey: "sk_test_123",
      model: "galyarder-route/fast",
    },
    modelAliases: {
      review: "cc/claude-sonnet-4-5-20250929",
    },
  });
});
