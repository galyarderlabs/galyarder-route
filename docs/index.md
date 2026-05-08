---
template: home.html
title: Galyarder Route
subtitle: A local-first route layer for model traffic, agent fleets, provider policy, and daily AI operations.
hide:
  - navigation
  - toc
---

<div class="groute-grid">
  <a class="groute-card" href="SETUP_GUIDE/">
    <strong>Start The Router</strong>
    <span>Run the local dashboard and expose one OpenAI-compatible endpoint for agent tools, SDKs, and automation.</span>
  </a>
  <a class="groute-card" href="CLI-TOOLS/">
    <strong>Wire Agent Clients</strong>
    <span>Connect Claude Code, Codex, Gemini CLI, OpenCode, Hermes, G-Agent, Cline, Cursor, and compatible clients.</span>
  </a>
  <a class="groute-card" href="AUTO-COMBO/">
    <strong>Control Model Policy</strong>
    <span>Use aliases, combos, fallback chains, quotas, health checks, and cost-aware routing without changing every client.</span>
  </a>
  <a class="groute-card" href="RESILIENCE_GUIDE/">
    <strong>Keep Sessions Alive</strong>
    <span>Route around provider errors, region problems, quota limits, cooldowns, and long-context handoffs.</span>
  </a>
</div>

## Start Here

1. [Getting Started](SETUP_GUIDE.md) - install and run Galyarder Route.
2. [CLI Tools](CLI-TOOLS.md) - point agent clients at the same route layer.
3. [API Reference](API_REFERENCE.md) - call the OpenAI-compatible and protocol bridge endpoints.
4. [Features](FEATURES.md) - inspect the dashboard surfaces and operating capabilities.

## Operating Model

Galyarder Route sits underneath a broader agent stack. Brave CDP can stay the human-facing cockpit, Camofox can stay the isolated automation lab, Playwright can stay deterministic QA, and cloud browsers can stay remote fallback. Galyarder Route handles model aliases, provider policy, traffic fallback, context controls, keys, logging, and quotas.

<p class="groute-note"><i>One browser or one model should not own every workflow. Route by use case, then keep the model traffic governed in one place.</i></p>
