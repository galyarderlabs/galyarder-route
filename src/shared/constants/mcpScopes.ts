/**
 * MCP Authorization Scopes — Defines permission scopes for each MCP tool.
 *
 * Each tool requires specific scopes to execute. API keys can be configured
 * with a subset of scopes to limit tool access (least-privilege).
 */

// ============ Scope Definitions ============

/** All available MCP scopes */
export const MCP_SCOPE_LIST = [
  "read:health",
  "read:combos",
  "write:combos",
  "read:quota",
  "read:usage",
  "read:models",
  "execute:completions",
  "execute:search",
  "write:budget",
  "write:resilience",
  "pricing:write",
  "read:cache",
  "write:cache",
  "read:compression",
  "write:compression",
  "read:proxies",
] as const;

export type McpScope = (typeof MCP_SCOPE_LIST)[number];

// ============ Tool → Scope Mapping ============

/** Maps each MCP tool to its required scopes */
export const MCP_TOOL_SCOPES: Record<string, readonly McpScope[]> = {
  // Phase 1: Essential Tools
  galyarder_route_get_health: ["read:health"],
  galyarder_route_list_combos: ["read:combos"],
  galyarder_route_get_combo_metrics: ["read:combos"],
  galyarder_route_switch_combo: ["write:combos"],
  galyarder_route_check_quota: ["read:quota"],
  galyarder_route_route_request: ["execute:completions"],
  galyarder_route_web_search: ["execute:search"],
  galyarder_route_cost_report: ["read:usage"],
  galyarder_route_list_models_catalog: ["read:models"],

  // Phase 2: Advanced Tools
  galyarder_route_simulate_route: ["read:health", "read:combos"],
  galyarder_route_set_budget_guard: ["write:budget"],
  galyarder_route_set_resilience_profile: ["write:resilience"],
  galyarder_route_test_combo: ["execute:completions", "read:combos"],
  galyarder_route_get_provider_metrics: ["read:health"],
  galyarder_route_best_combo_for_task: ["read:combos", "read:health"],
  galyarder_route_explain_route: ["read:health", "read:usage"],
  galyarder_route_get_session_snapshot: ["read:usage"],
  galyarder_route_db_health_check: ["read:health", "write:resilience"],
  galyarder_route_sync_pricing: ["pricing:write"],
  galyarder_route_cache_stats: ["read:cache"],
  galyarder_route_cache_flush: ["write:cache"],
  galyarder_route_compression_status: ["read:compression"],
  galyarder_route_compression_configure: ["write:compression"],
  galyarder_route_set_compression_engine: ["write:compression"],
  galyarder_route_list_compression_combos: ["read:compression"],
  galyarder_route_compression_combo_stats: ["read:compression"],
  galyarder_route_oneproxy_fetch: ["read:proxies"],
  galyarder_route_oneproxy_rotate: ["read:proxies"],
  galyarder_route_oneproxy_stats: ["read:proxies"],
} as const;

// ============ Scope Groups ============

/** Preset scope bundles for common use cases */
export const MCP_SCOPE_PRESETS = {
  /** Read-only access to all health, combo, quota, and usage data */
  readonly: [
    "read:health",
    "read:combos",
    "read:quota",
    "read:usage",
    "read:models",
    "read:cache",
    "read:compression",
  ] as const satisfies readonly McpScope[],

  /** Full access including writes and execution */
  full: [...MCP_SCOPE_LIST] as McpScope[],

  /** Monitoring only — health and metrics */
  monitor: [
    "read:health",
    "read:quota",
    "read:usage",
    "read:cache",
    "read:compression",
  ] as const satisfies readonly McpScope[],

  /** Agent — can execute completions and read state */
  agent: [
    "read:health",
    "read:combos",
    "read:quota",
    "read:usage",
    "read:models",
    "read:cache",
    "read:compression",
    "execute:completions",
    "execute:search",
  ] as const satisfies readonly McpScope[],
} as const;

// ============ Helpers ============

/**
 * Check if a set of granted scopes satisfies the required scopes for a tool.
 */
export function hasRequiredScopes(grantedScopes: readonly string[], toolName: string): boolean {
  const required = MCP_TOOL_SCOPES[toolName];
  if (!required) return false;
  const granted = new Set(grantedScopes);
  return required.every((scope) => granted.has(scope));
}

/**
 * Get the list of missing scopes for a tool given granted scopes.
 */
export function getMissingScopes(grantedScopes: readonly string[], toolName: string): string[] {
  const required = MCP_TOOL_SCOPES[toolName];
  if (!required) return [];
  const granted = new Set(grantedScopes);
  return required.filter((scope) => !granted.has(scope));
}
