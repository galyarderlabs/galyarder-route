import test from "node:test";
import assert from "node:assert/strict";

Object.assign(process.env, {
  CLAUDE_OAUTH_CLIENT_ID: "9d1c250a-e61b-44d9-88ed-5944d1962f5e",
  CODEX_OAUTH_CLIENT_ID: "app_EMoamEEZ73f0CkXaXp7hrann",
  GEMINI_OAUTH_CLIENT_ID:
    "test-google-oauth-client-id",
  GEMINI_OAUTH_CLIENT_SECRET: "test-google-oauth-client-secret",
  GEMINI_CLI_OAUTH_CLIENT_ID:
    "test-google-oauth-client-id",
  GEMINI_CLI_OAUTH_CLIENT_SECRET: "test-google-oauth-client-secret",
  QWEN_OAUTH_CLIENT_ID: "f0304373b74a44d2b584a3fb70ca9e56",
  KIMI_CODING_OAUTH_CLIENT_ID: "17e5f671-d194-4dfb-9706-5516cb48c098",
  ANTIGRAVITY_OAUTH_CLIENT_ID:
    "test-antigravity-google-oauth-client-id",
  ANTIGRAVITY_OAUTH_CLIENT_SECRET: "test-antigravity-google-oauth-client-secret",
  GITHUB_OAUTH_CLIENT_ID: "Iv1.b507a08c87ecfe98",
});

const { OAUTH_ENDPOINTS } = await import("../../open-sse/config/constants.ts");
const { qoder } = await import("../../src/lib/oauth/providers/qoder.ts");
const { QODER_CONFIG } = await import("../../src/lib/oauth/constants/oauth.ts");

test("Qoder OAuth defaults no longer point to qoder.cn", () => {
  assert.doesNotMatch(QODER_CONFIG.authorizeUrl || "", /qoder\.cn/i);
  assert.doesNotMatch(QODER_CONFIG.tokenUrl || "", /qoder\.cn/i);
  assert.doesNotMatch(QODER_CONFIG.userInfoUrl || "", /qoder\.cn/i);
  assert.doesNotMatch(OAUTH_ENDPOINTS.qoder.auth || "", /qoder\.cn/i);
  assert.doesNotMatch(OAUTH_ENDPOINTS.qoder.token || "", /qoder\.cn/i);
});

test("Qoder OAuth provider returns null when browser auth is not configured", () => {
  if (!QODER_CONFIG.enabled) {
    assert.equal(qoder.buildAuthUrl(QODER_CONFIG, "http://localhost:8080/callback", "state"), null);
    return;
  }

  const authUrl = qoder.buildAuthUrl(QODER_CONFIG, "http://localhost:8080/callback", "state");
  assert.equal(typeof authUrl, "string");
  assert.doesNotMatch(authUrl || "", /qoder\.cn/i);
});
