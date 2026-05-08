/**
 * Model Deprecation Auto-Forward — Feature 2
 *
 * Maps deprecated model IDs to their replacements so user configs
 * don't break when providers rename or retire models.
 *
 * Supports both built-in aliases (static) and custom aliases (persisted via Settings API).
 */

// ── Built-in Deprecation Aliases ────────────────────────────────────────────
// These are known renames/retirements across providers.
// Format: deprecated ID → current ID
const BUILT_IN_ALIASES: Record<string, string> = {
  // Gemini legacy → current
  "gemini-pro": "gemini-2.5-pro",
  "gemini-pro-vision": "gemini-2.5-pro",
  "gemini-1.5-pro": "gemini-2.5-pro",
  "gemini-1.5-flash": "gemini-2.5-flash",
  "gemini-1.0-pro": "gemini-2.5-pro",
  "gemini-2.0-flash": "gemini-2.5-flash",
  // Claude legacy → current
  "claude-3-opus-20240229": "claude-opus-4-20250514",
  "claude-3-sonnet-20240229": "claude-sonnet-4-20250514",
  "claude-3-haiku-20240307": "claude-3-5-sonnet-20241022",
  "claude-3-5-sonnet-latest": "claude-sonnet-4-20250514",
  "claude-3-5-haiku-latest": "claude-3-5-sonnet-20241022",

  // OpenAI legacy → current
  "gpt-4-turbo-preview": "gpt-4-turbo",
  "gpt-4-0125-preview": "gpt-4-turbo",
  "gpt-4-1106-preview": "gpt-4-turbo",
  "gpt-3.5-turbo-0125": "gpt-3.5-turbo",

  // Galyarder Route short-alias policy
  "gpt-3.5-turbo": "cx/gpt-3.5-turbo",
  "gpt-4": "cx/gpt-4",
  "gpt-4-turbo": "cx/gpt-4-turbo",
  "gpt-4.1": "cx/gpt-4.1",
  "gpt-4.1-mini": "cx/gpt-4.1-mini",
  "gpt-4.1-nano": "cx/gpt-4.1-nano",
  "gpt-4o": "cx/gpt-4o",
  "gpt-4o-mini": "cx/gpt-4o-mini",
  "gpt-5": "cx/gpt-5",
  "gpt-5-codex": "cx/gpt-5-codex",
  "gpt-5-mini": "cx/gpt-5-mini",
  "gpt-5-nano": "cx/gpt-5-nano",
  "gpt-5-pro": "cx/gpt-5-pro",
  "gpt-5.1": "cx/gpt-5.1",
  "gpt-5.1-codex": "cx/gpt-5.1-codex",
  "gpt-5.1-codex-max": "cx/gpt-5.1-codex-max",
  "gpt-5.1-codex-mini": "cx/gpt-5.1-codex-mini",
  "gpt-5.2": "cx/gpt-5.2",
  "gpt-5.2-codex": "cx/gpt-5.2-codex",
  "gpt-5.2-pro": "cx/gpt-5.2-pro",
  "gpt-5.3-codex": "cx/gpt-5.3-codex",
  "gpt-5.4": "cx/gpt-5.4",
  "gpt-5.4-mini": "cx/gpt-5.4-mini",
  "gpt-5.4-nano": "cx/gpt-5.4-nano",
  "gpt-5.4-pro": "cx/gpt-5.4-pro",
  "gpt-5.5": "cx/gpt-5.5",
  "gpt-5.5-pro": "cx/gpt-5.5-pro",
  o1: "cx/o1",
  "o1-pro": "cx/o1-pro",
  o3: "cx/o3",
  "o3-mini": "cx/o3-mini",
  "o3-pro": "cx/o3-pro",
  "o4-mini": "cx/o4-mini",
  "claude-haiku-4.5": "github/claude-haiku-4.5",
  "claude-opus-4.1": "github/claude-opus-41",
  "claude-opus-4.5": "github/claude-opus-4.5",
  "claude-opus-4.6": "github/claude-opus-4.6",
  "claude-opus-4.7": "github/claude-opus-4.7",
  "claude-opus-41": "github/claude-opus-41",
  "claude-sonnet-4": "github/claude-sonnet-4",
  "claude-sonnet-4.5": "github/claude-sonnet-4.5",
  "claude-sonnet-4.6": "github/claude-sonnet-4.6",
  "gemini-2.5-flash": "gemini-cli/gemini-2.5-flash",
  "gemini-2.5-flash-lite": "gemini-cli/gemini-2.5-flash-lite",
  "gemini-2.5-pro": "gemini-cli/gemini-2.5-pro",
  "gemini-3-flash-preview": "gemini-cli/gemini-3-flash-preview",
  "gemini-3-pro-high": "antigravity/gemini-3-pro-preview",
  "gemini-3-pro-low": "antigravity/gemini-3.1-pro-low",
  "gemini-3-pro-preview": "gemini-cli/gemini-3-pro-preview",
  "gemini-3.1-flash-lite-preview": "gemini-cli/gemini-3.1-flash-lite-preview",
  "gemini-3.1-pro": "gemini-cli/gemini-3.1-pro-preview",
  "gemini-3.1-pro-preview": "gemini-cli/gemini-3.1-pro-preview",
  "gemini-3.1-pro-preview-customtools": "antigravity/gemini-3-pro-preview",

  // Kimi/Moonshot — Fireworks long-path aliases (#265)
  "accounts/fireworks/models/kimi-k2p5": "moonshotai/Kimi-K2.5",
  "fireworks/accounts/fireworks/models/kimi-k2p5": "moonshotai/Kimi-K2.5",
  "kimi-k2p5": "moonshotai/Kimi-K2.5",
  "accounts/fireworks/models/kimi-k2": "moonshotai/Kimi-K2",
  "fireworks/accounts/fireworks/models/kimi-k2": "moonshotai/Kimi-K2",
  "kimi-k2": "moonshotai/Kimi-K2",

  // Mistral short aliases
  "mistral-large": "mistral-large-latest",
  "mistral-small": "mistral-small-latest",
  codestral: "codestral-latest",

  // Llama short aliases
  "llama-3.3": "llama-3.3-70b-versatile",
  "llama-3-70b": "llama-3.3-70b-versatile",
  "llama-3-8b": "llama3-8b-8192",
};

// ── Custom Aliases (persisted via Settings API) ─────────────────────────────
let _customAliases: Record<string, string> = {};

/**
 * Set custom aliases (called from settings API or startup).
 */
export function setCustomAliases(aliases: Record<string, string>): void {
  _customAliases = { ...aliases };
}

/**
 * Get current custom aliases.
 */
export function getCustomAliases(): Record<string, string> {
  return { ..._customAliases };
}

/**
 * Get the full alias map (built-in + custom).
 * Custom aliases take precedence over built-in.
 */
export function getAllAliases(): Record<string, string> {
  return { ...BUILT_IN_ALIASES, ..._customAliases };
}

/**
 * Resolve a model alias to its current ID.
 * Custom aliases override built-in ones.
 *
 * @param {string} modelId - The model ID to resolve
 * @returns {string} The resolved model ID, or the original if not deprecated
 */
export function resolveModelAlias(modelId: string): string {
  if (!modelId) return modelId;

  // Check custom aliases first (higher priority)
  if (_customAliases[modelId]) return _customAliases[modelId];

  // Then check built-in
  if (BUILT_IN_ALIASES[modelId]) return BUILT_IN_ALIASES[modelId];

  return modelId;
}

/**
 * Get a deprecation notice if the model is deprecated.
 *
 * @param {string} modelId - The model ID to check
 * @returns {string | null} Deprecation message or null if not deprecated
 */
export function getDeprecationNotice(modelId: string): string | null {
  if (!modelId) return null;

  const resolved = resolveModelAlias(modelId);
  if (resolved === modelId) return null;

  return `Model "${modelId}" is deprecated. Forwarding to "${resolved}".`;
}

/**
 * Check if a model is deprecated.
 */
export function isDeprecated(modelId: string): boolean {
  return getDeprecationNotice(modelId) !== null;
}

/**
 * Add a custom alias.
 */
export function addCustomAlias(from: string, to: string): void {
  _customAliases[from] = to;
}

/**
 * Remove a custom alias.
 */
export function removeCustomAlias(from: string): boolean {
  if (_customAliases[from]) {
    delete _customAliases[from];
    return true;
  }
  return false;
}

/**
 * Get the built-in aliases (read-only reference).
 */
export function getBuiltInAliases(): Record<string, string> {
  return { ...BUILT_IN_ALIASES };
}
