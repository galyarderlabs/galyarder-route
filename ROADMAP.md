# Galyarder Route — Roadmap

Galyarder Route is a self-hosted, local-first routing layer for model and agent
traffic. It sits between your tools and upstream providers, then exposes one
consistent surface: OpenAI-compatible chat, completions, embeddings, images,
audio, video, rerank, batch, and moderation endpoints, plus Anthropic Messages
and Gemini / OpenAI Responses translation. It is for solo developers and small
teams who run several coding agents at once — Claude Code, Codex, Gemini CLI,
OpenCode, Hermes, G-Agent, MCP clients — and who do not want every tool to keep
its own API keys, aliases, quotas, and fallback rules. The problem it solves is
drift: without a shared policy layer, each agent improvises its own provider
setup, and no one can see spend, health, or routing behavior in one place.

## Where this comes from

Galyarder Route is a modified derivative of [OmniRoute](https://github.com/diegosouzapw/OmniRoute),
licensed under MIT. The provider-routing core, the format-translation layer, and
the provider catalog originate from that project and have been renamed,
rebranded, and extended here. Upstream copyright is retained in `LICENSE`
alongside the notice for Galyarder Labs modifications, and the lineage is stated
in `NOTICE` and the README. The direction this repository owns is the operating
policy around that core: stable aliases, combo strategies, resilience, context
compression, and the agent surfaces (MCP, A2A) that turn a proxy into something
an agent fleet can share.

## Where it is now

The product is real and broad. The current version is `3.7.9`. The codebase is
TypeScript on Next.js 16 (`^16.2.3`, React 19), with a streaming and translation
core in `open-sse/`, SQLite (`better-sqlite3`) for local state, and an Electron
desktop shell under `electron/`. Verified against the repository tree:

- 24 executor modules under `open-sse/executors/` and a provider catalog in
  `open-sse/config/providerRegistry.ts`.
- 13 combo routing strategies declared in
  `src/shared/constants/routingStrategies.ts` (priority, weighted, round-robin,
  context-relay, fill-first, p2c, random, least-used, cost-optimized,
  strict-random, auto, lkgp, context-optimized).
- An MCP server with 37 tools across stdio and HTTP transports
  (`open-sse/mcp-server/`, documented in `docs/MCP-SERVER.md`).
- An A2A v0.3 server (JSON-RPC 2.0 plus SSE) with task lifecycle and routing
  metadata (`src/app/a2a/route.ts`, `src/app/.well-known/agent.json/route.ts`,
  `docs/A2A-SERVER.md`). It is disabled by default and enabled per the Endpoints
  toggle.
- A dashboard covering providers, combos, analytics, health, logs, context
  compression, costs, usage, CLI setup, and system status under
  `src/app/(dashboard)/dashboard/`, served by 271 API route handlers under
  `src/app/api/`.
- A prompt compression pipeline (Caveman, RTK, stacked) in
  `open-sse/services/compression/`.
- 31 documents in `docs/`, and `docs/i18n/` carrying 40 locales.
- A unit suite of 513 test files under `tests/unit/`.

Parts of this are still thin or inconsistent:

- **A stray root artifact remains.** `test-kiro.ts` sits at the repository root
  and does not belong to the product. (Earlier stray files such as
  `pr_metadata.json` and `news.json` are no longer in the tree.)
- **There is no pull request test gate.** The only workflow is
  `.github/workflows/docs-pages.yml`. Lint, typecheck, and the unit suite run
  from local husky hooks (`pre-commit`, `pre-push`) and by habit, not by CI.
- **The contribution surface is incomplete.** There are no issue or pull request
  templates under `.github/`, and no in-repo roadmap or PRD. This file is the
  first.
- **Coverage is honest but modest.** `docs/COVERAGE_PLAN.md` puts the
  project-wide baseline (source-only, including `open-sse`) at 56.95%
  statements, 66.05% branches, 57.80% functions.
- **The supported Node.js range drifts.** `package.json` `engines` states
  `>=20.20.2 <21 || >=22.22.2 <23 || >=24.0.0 <27`; `README.md` states
  `>=24.0.0 <27`; `AGENTS.md` states `>=24.0.0 <25`. The three do not agree.
- **Compression is one phase from its stated end state.** Per-model adaptive and
  ML-based pruning are marked Planned (Phase 4) in `docs/COMPRESSION_GUIDE.md`.
- **Usage history does not record the routing strategy.** A `TODO` in
  `src/lib/db/settings.ts` notes that a `combo_strategy` column is still missing
  from `usage_history`, so analytics attributes every request to `direct`.

## Now

- **Add a pull request test gate.** Wire lint, core typecheck, and the unit suite
  into a GitHub Actions workflow so a change cannot land without passing the
  checks that already exist as npm scripts. This is the highest-leverage gap:
  every other item is safer once CI enforces it.
- **Clean the repository root.** Remove `test-kiro.ts` and add a guard so
  generated working files do not get committed. A clean root is the first thing a
  new contributor reads.
- **Reconcile the supported Node.js range.** Make `README.md`, `AGENTS.md`, and
  `package.json` agree on one authoritative range, and have `check:node-runtime`
  enforce it. Today the install instructions are ambiguous.
- **Add issue and pull request templates.** A short template per type keeps new
  reports in the format the `.agents/workflows/` triage flow already expects
  (version, Node version, OS, install method, reproduction steps, logs).
- **Record the routing strategy in usage history.** Close the `TODO` in
  `src/lib/db/settings.ts` by adding a `combo_strategy` column and populating it,
  so analytics can attribute usage to a strategy instead of a model string alone.

## Next

- **Merge coverage into one report.** Follow `docs/COVERAGE_PLAN.md` and combine
  the Node unit suite and Vitest into a single source-only number, then raise it
  through the documented phases toward the 90% statement target. One number is
  easier to trust than three.
- **Ship per-model adaptive compression.** Complete Phase 4 of the compression
  pipeline so compression rules respond to the model and the prompt, not only to
  a global mode.
- **Make the A2A surface first-class in the docs.** A2A is off by default and
  easy to miss. A worked example from agent card discovery to a completed task,
  next to MCP, would make the agent-to-agent path usable without reading source.
- **Harden the provider assessment loop.** The auto-assessment engine and its RFC
  describe models that fail silently. Keep the assessor, categorizer, and
  self-healer honest with tests that pin the observed failure modes.
- **Tighten repository hygiene checks.** Extend the pre-commit hooks and CI to
  catch generated-file drift, docs-sync drift, and unsafe filenames before merge.

## Later

- **Make policy inspectable end to end.** The router already emits correlation
  IDs, request telemetry, and policy verdicts. The longer goal is a single trace
  that shows why a request went where it went, from alias to provider to cost.
- **Broaden the protocol surface beyond coding agents.** The route layer is
  written for any model client, not only CLI coding tools. Real examples for
  automation, QA, and product services would test that claim.
- **Keep the local-first promise as scope grows.** More providers, more
  translation, and more context tooling should not require a hosted control
  plane. The constraint is part of the design.

## Not planned

- **No hosted cloud service.** The router runs on your workstation, in Docker, or
  on your own VPS. There is no plan to turn the routing core into managed SaaS.
- **No replacement for upstream provider control planes.** SLA management and
  provider-side administration stay with the provider.
- **No shipping of external CLI binaries.** Claude Code, Codex CLI, and the other
  clients keep their own distribution; Galyarder Route configures them, it does
  not bundle them.
- **No closed or source-available license.** The project is MIT and stays MIT.
- **No fabricated performance claims.** Routing, compression, and cost behavior
  are reported from your own logs, not from marketing numbers.

## How to follow along

Read the docs at https://galyarderlabs.github.io/galyarder-route/ and the `docs/`
directory in the repo. Watch pull requests and releases on GitHub for what is
landing. Open an issue for a concrete bug or a scoped proposal, and send a pull
request against `main` from a feature branch. Because the project is small and
early, a clear, well-scoped issue is the fastest way to get a change reviewed.
