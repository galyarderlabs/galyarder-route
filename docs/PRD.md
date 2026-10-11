# Galyarder Route — Product Requirements

**Status**: Active
**Scope**: This document defines what Galyarder Route is, who it serves, and the
requirements its routing, policy, and operations surfaces must meet. It covers
the self-hosted router and its dashboard, not the individual upstream providers
or the external agent clients it configures.

## Problem

Modern agent work does not run on one model and one API key. A real stack mixes
premium models for planning and review, cheaper models for bulk work, and
provider-specific routes for tool behavior. Each client — Claude Code, Codex,
Gemini CLI, OpenCode, Hermes, G-Agent, an MCP client — tends to hold its own
keys, its own aliases, and its own fallback logic.

That produces concrete failures:

- Provider names and model IDs change, and every client breaks separately.
- Quota, region, auth, and latency failures have no shared fallback, so a session
  dies where another route would have worked.
- There is no single place to see spend, health, or routing behavior.
- Long sessions carry expensive context with no compression or handoff policy.
- Tool and agent traffic is unauditable: no correlation ID, no policy verdict,
  no record of why a request went where it went.

The problem is not "call a model." It is running model traffic under one
inspectable policy without rewriting every client.

## Who it is for

- A solo developer running several coding agents at once who wants one endpoint,
  one key, and one quota view instead of five disconnected setups.
- A small team sharing provider accounts who need aliases that stay stable when
  upstream names change, and fallback that keeps work alive when a provider
  fails.
- An operator running the router on a workstation, in Docker, or on a VPS who
  needs health, spend, logs, and policy controls in one dashboard.
- An automation or QA system that needs isolated sessions while still using the
  same model policy as interactive work.

## Goals

- One governed model surface. Any supported client speaks its own protocol, and
  the router normalizes upstream behavior behind a stable local endpoint.
- Stable routing policy. Aliases, combos, quotas, and fallback rules live in one
  place and do not change when a provider does.
- Predictable resilience. Failures degrade through fallback and cooldown instead
  of surfacing raw provider errors.
- Inspectable operations. Logs, spend, health, and routing decisions are visible
  without reading the source.
- Local-first deployment. The router runs on hardware the user controls, with no
  hosted control plane required.

## Non-goals

- Hosted or managed SaaS for the routing core.
- Provider-side SLA management or administration.
- Bundling or distributing the external agent clients themselves.
- Model training or fine-tuning. This layer routes and governs traffic.
- A general project tracker or workflow tool.

## Requirements

### API surface

- **R1 — One compatible endpoint.** `[implemented]` Expose an OpenAI-compatible
  surface for chat, completions, embeddings, images, audio, video, rerank,
  batch, and moderation, so existing SDKs and CLI tools work without changes.
  Evidence: `open-sse/handlers/` (`chatCore.ts`, `embeddings.ts`,
  `imageGeneration.ts`, `audioSpeech.ts`, `videoGeneration.ts`, `rerank.ts`,
  `moderations.ts`) and `docs/API_REFERENCE.md`.
- **R2 — Protocol translation.** `[implemented]` Accept Anthropic Messages and
  Gemini / OpenAI Responses traffic and translate request and response shapes in
  both directions, including streaming. Evidence: `open-sse/translator/request/`
  and `open-sse/translator/response/`, with per-pair unit tests under
  `tests/unit/translator-*.test.ts`.
- **R3 — Model catalog and aliases.** `[implemented]` Serve a model catalog and
  resolve short aliases (`gpt-*`, `o*`, `claude-*`, `gemini-*`, project routes)
  to concrete provider backends. Evidence: `src/app/api/models/` (catalog,
  alias, openrouter-catalog), `src/shared/utils/providerModelAliases.ts`, and
  `open-sse/config/providerRegistry.ts`.

### Routing and policy

- **R4 — Combo strategies.** `[implemented]` Support multiple routing strategies
  with automatic fallback across combo steps. Evidence:
  `src/shared/constants/routingStrategies.ts` declares 13 values (priority,
  weighted, round-robin, context-relay, fill-first, p2c, random, least-used,
  cost-optimized, strict-random, auto, lkgp, context-optimized); implemented in
  `open-sse/services/combo.ts` and `open-sse/services/autoCombo/`.
- **R5 — Account and quota policy.** `[implemented]` Select among multiple
  accounts per provider, skip exhausted quota, and track spend against limits.
  Evidence: `open-sse/services/accountSelector.ts`,
  `open-sse/services/accountFallback.ts`, `open-sse/services/quotaMonitor.ts`,
  `open-sse/services/quotaPreflight.ts`.
- **R6 — Strategy attribution in usage history.** `[planned]` Record which
  routing strategy served a request in `usage_history`, so analytics can
  attribute usage to a strategy and not only to a model string. Evidence: a
  `TODO` in `src/lib/db/settings.ts` notes the `combo_strategy` column is
  missing and currently reports every request as `direct`.
- **R7 — Auto-combo and self-healing.** `[partial]` Select providers by a
  multi-factor score and exclude failing targets temporarily. Evidence: the
  scoring, task-fitness, and engine modules exist
  (`open-sse/services/autoCombo/`), and an auto-assessment engine was added for
  combo self-healing (CHANGELOG 3.7.9); the assessment and self-healing loop
  described in `docs/RFC-AUTO-ASSESSMENT.md` is still maturing.

### Resilience

- **R8 — Cooldown, circuit breaker, and fallback.** `[implemented]` Cool down
  failing connections with backoff, trip a provider-level circuit breaker only
  after fallback is exhausted, and rotate to the next target. Evidence:
  `src/sse/services/cooldownAwareRetry.ts`,
  `open-sse/services/rateLimitManager.ts`,
  `open-sse/services/emergencyFallback.ts`, `src/shared/utils/circuitBreaker.ts`.
- **R9 — Session continuity.** `[implemented]` Provide context relay and
  last-known-good routing so a long session survives an account rotation.
  Evidence: `open-sse/services/contextHandoff.ts`, the `context-relay` and
  `lkgp` strategies, and `docs/features/context-relay.md`.

### Context and compression

- **R10 — Prompt compression pipeline.** `[implemented]` Offer Off, Lite,
  Standard, Aggressive, Ultra, RTK, and Stacked modes, with combo assignment,
  language packs, and per-request savings reporting. Evidence:
  `open-sse/services/compression/` (including `engines/rtk/` with a filter
  catalog and language rule packs) and `docs/COMPRESSION_GUIDE.md`, whose Phase 1
  through Phase 3 are marked shipped.
- **R11 — Adaptive compression.** `[planned]` Make compression respond to the
  model and prompt, not only to a global mode. Evidence:
  `docs/COMPRESSION_GUIDE.md` marks Phase 4 (per-model adaptive, ML-based
  pruning) as Planned.

### Agent surfaces

- **R12 — MCP server.** `[implemented]` Expose routing, cache, compression,
  memory, skills, and proxy operations as MCP tools over stdio and HTTP
  transports, with scoped authentication. Evidence:
  `open-sse/mcp-server/` (`server.ts`, `httpTransport.ts`, `scopeEnforcement.ts`,
  `tools/`) and `docs/MCP-SERVER.md`, which documents 37 tools.
- **R13 — A2A server.** `[implemented]` Expose an A2A v0.3 agent card and
  JSON-RPC 2.0 methods (`message/send`, `message/stream`, `tasks/get`,
  `tasks/cancel`) with task lifecycle and routing metadata. Disabled by default;
  enabled per the Endpoints toggle. Evidence: `src/app/a2a/route.ts`,
  `src/app/.well-known/agent.json/route.ts`, `docs/A2A-SERVER.md`.

### Operations

- **R14 — Dashboard.** `[implemented]` Provide one console for provider setup,
  combos, analytics, health, logs, quota, compression, CLI tools, and system
  status. Evidence: pages under `src/app/(dashboard)/dashboard/` (providers,
  combos, analytics, health, logs, usage, costs, context, cli-tools, settings)
  served by 271 API route handlers under `src/app/api/`.
- **R15 — Observability.** `[implemented]` Emit correlation IDs, request
  telemetry (p50/p95/p99 latency), policy verdicts, and cost records that can be
  inspected per request. Evidence: `src/shared/middleware/correlationId.ts`,
  `src/shared/utils/requestTelemetry.ts`,
  `src/shared/utils/structuredLogger.ts`, `docs/A2A-SERVER.md` policy verdicts.
- **R16 — Local persistence.** `[implemented]` Store providers, keys, aliases,
  combos, settings, and pricing in local SQLite under a configurable data
  directory, with optional cloud sync. Evidence: `better-sqlite3` in
  `package.json`, `src/app/api/settings/`, `src/app/api/db-backups/`,
  `src/shared/services/cloudSyncScheduler.ts`.

### Delivery and hygiene

- **R17 — Pull request test gate.** `[planned]` Run lint, core typecheck, and the
  unit suite on every pull request so a change cannot land unchecked. Evidence:
  the only workflow is `.github/workflows/docs-pages.yml`; the checks exist as
  npm scripts and husky hooks but no CI gate runs them.
- **R18 — Clean repository root.** `[partial]` Keep generated and unrelated
  working files out of the tracked root. Evidence: `test-kiro.ts` remains at the
  root; earlier stray files (`pr_metadata.json`, `news.json`) are no longer
  present.
- **R19 — Single-source runtime and version facts.** `[partial]` Keep the
  supported Node.js range and version references consistent across `README.md`,
  `AGENTS.md`, `package.json`, and the changelog, and enforce them in a check.
  Evidence: the three files currently disagree (`>=24.0.0 <27` in the README,
  `>=24.0.0 <25` in `AGENTS.md`, `>=20.20.2 <21 || >=22.22.2 <23 || >=24.0.0 <27`
  in `package.json`), although `check:node-runtime` exists.

## Success signals

- A new user can install, start the router, and point a first agent client at it
  using the documented steps without reading source.
- A provider failure degrades to fallback instead of failing the request, and the
  fallback path is visible in logs.
- Aliases survive a provider rename without a client-side change.
- Spend, health, and routing behavior for a day of agent work are readable from
  one dashboard view.
- A contributor can tell, before opening a pull request, what checks will run and
  what the project expects.

## Open questions

- Should the A2A surface be enabled by default, or stay opt-in?
- Which coverage number is authoritative once the Node and Vitest suites are
  merged into one report?
- How much of the auto-assessment and self-healing loop should run
  automatically, and how much should stay an operator-triggered action?
- Should the supported Node.js range narrow to one LTS line, or keep tracking
  several?
- Where should operational examples live: `docs/`, the docs site, or a separate
  example repository?

---

**Lineage note.** Galyarder Route is a modified derivative of
[OmniRoute](https://github.com/diegosouzapw/OmniRoute), MIT-licensed. The
provider-routing core, format-translation layer, and provider catalog originate
from that project. Upstream copyright is retained in `LICENSE`; the notice is in
`NOTICE`.
