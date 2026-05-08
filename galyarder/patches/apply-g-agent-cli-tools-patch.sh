#!/usr/bin/env bash
set -euo pipefail

SERVICE="${OMNIROUTE_SERVICE:-omniroute.service}"
LOGO_SRC="${G_AGENT_LOGO_SRC:-$HOME/projects/galyarder-agent/docs/assets/logo.webp}"
G_AGENT_BIN="${G_AGENT_BIN:-$HOME/.local/bin/g-agent}"
HERMES_BIN="${HERMES_BIN:-$HOME/.local/bin/hermes}"
ENV_FILE="${OMNIROUTE_ENV_FILE:-$HOME/.omniroute/.env}"
DB_FILE="${OMNIROUTE_DB_FILE:-$HOME/.omniroute/storage.sqlite}"

find_omniroute_root() {
  local unit exec_path root
  unit="$(systemctl --user cat "$SERVICE" 2>/dev/null || true)"
  exec_path="$(printf '%s\n' "$unit" | sed -n 's#.* \(/[^ ]*/lib/node_modules/omniroute/bin/omniroute\.mjs\).*#\1#p' | head -n1)"
  if [[ -n "$exec_path" ]]; then
    root="$(dirname "$(dirname "$exec_path")")"
    if [[ -d "$root/app/.next" ]]; then
      printf '%s\n' "$root"
      return 0
    fi
  fi

  if command -v omniroute >/dev/null 2>&1; then
    exec_path="$(readlink -f "$(command -v omniroute)")"
    root="$(dirname "$(dirname "$exec_path")")"
    if [[ -d "$root/app/.next" ]]; then
      printf '%s\n' "$root"
      return 0
    fi
  fi

  printf 'Could not locate OmniRoute npm package root.\n' >&2
  return 1
}

find_service_node() {
  local unit node_path
  unit="$(systemctl --user cat "$SERVICE" 2>/dev/null || true)"
  node_path="$(printf '%s\n' "$unit" | sed -n 's#^ExecStart=\([^ ]*/node\) .*#\1#p' | head -n1)"
  if [[ -n "$node_path" && -x "$node_path" ]]; then
    printf '%s\n' "$node_path"
    return 0
  fi
  command -v node
}

ROOT="${OMNIROUTE_ROOT:-$(find_omniroute_root)}"
APP="$ROOT/app"
NODE_BIN="${OMNIROUTE_NODE_BIN:-$(find_service_node)}"
NODE_DIR="$(dirname "$NODE_BIN")"
STAMP="$(date +%Y%m%d-%H%M%S)"

printf 'Patching OmniRoute at: %s\n' "$ROOT"

if [[ ! -d "$APP/.next" ]]; then
  printf 'Missing Next build under %s/.next\n' "$APP" >&2
  exit 1
fi

if [[ -f "$LOGO_SRC" ]]; then
  install -m 0644 "$LOGO_SRC" "$APP/public/providers/g-agent.webp"
  rm -f "$APP/public/providers/g-agent.svg"
else
  printf 'Warning: logo source not found: %s\n' "$LOGO_SRC" >&2
fi

mkdir -p "$(dirname "$ENV_FILE")"
touch "$ENV_FILE"
if grep -q '^CLI_G_AGENT_BIN=' "$ENV_FILE"; then
  sed -i "s#^CLI_G_AGENT_BIN=.*#CLI_G_AGENT_BIN=$G_AGENT_BIN#" "$ENV_FILE"
else
  printf '\nCLI_G_AGENT_BIN=%s\n' "$G_AGENT_BIN" >> "$ENV_FILE"
fi
if grep -q '^CLI_HERMES_BIN=' "$ENV_FILE"; then
  sed -i "s#^CLI_HERMES_BIN=.*#CLI_HERMES_BIN=$HERMES_BIN#" "$ENV_FILE"
else
  printf '\nCLI_HERMES_BIN=%s\n' "$HERMES_BIN" >> "$ENV_FILE"
fi

ensure_better_sqlite3_binding() {
  local root_pkg app_pkg
  root_pkg="$ROOT/node_modules/better-sqlite3"
  app_pkg="$APP/node_modules/better-sqlite3"
  if [[ ! -d "$root_pkg" || ! -d "$app_pkg" ]]; then
    return 0
  fi
  if "$NODE_BIN" -e "const Database=require('$app_pkg'); new Database(':memory:').prepare('select 1').get();" >/dev/null 2>&1; then
    printf 'better-sqlite3 native binding: ok\n'
    return 0
  fi
  printf 'better-sqlite3 native binding: rebuilding for %s\n' "$("$NODE_BIN" -p 'process.version + " abi=" + process.versions.modules')"
  (cd "$ROOT" && env PATH="$NODE_DIR:/usr/local/bin:/usr/bin:/bin" npm rebuild better-sqlite3 --build-from-source)
  rm -rf "$app_pkg/build"
  cp -a "$root_pkg/build" "$app_pkg/"
  "$NODE_BIN" -e "const Database=require('$app_pkg'); new Database(':memory:').prepare('select 1').get();" >/dev/null
  printf 'better-sqlite3 native binding: repaired\n'
}

ensure_better_sqlite3_binding

node - "$APP" "$STAMP" <<'NODE'
const fs = require('fs');
const path = require('path');

const app = process.argv[2];
const stamp = process.argv[3];

function walk(dir, out = []) {
  for (const name of fs.readdirSync(dir)) {
    const p = path.join(dir, name);
    const st = fs.statSync(p);
    if (st.isDirectory()) walk(p, out);
    else if (p.endsWith('.js')) out.push(p);
  }
  return out;
}

function firstFile(dir, pred) {
  const files = walk(dir);
  const hit = files.find((f) => pred(f, fs.readFileSync(f, 'utf8')));
  if (!hit) throw new Error(`Could not find target under ${dir}`);
  return hit;
}

function matchingFiles(dir, pred) {
  return walk(dir).filter((f) => pred(f, fs.readFileSync(f, 'utf8')));
}

function backup(file) {
  const bak = `${file}.bak-gagent-reapply-${stamp}`;
  if (!fs.existsSync(bak)) fs.copyFileSync(file, bak);
}

function replaceOnce(file, from, to, label) {
  let s = fs.readFileSync(file, 'utf8');
  if (s.includes(to)) return `${label}: already`;
  const count = s.split(from).length - 1;
  if (count !== 1) throw new Error(`${label}: expected 1 match, got ${count}`);
  backup(file);
  fs.writeFileSync(file, s.replace(from, to));
  return `${label}: patched`;
}

function replaceRegex(file, regex, to, alreadyNeedle, label) {
  let s = fs.readFileSync(file, 'utf8');
  if (alreadyNeedle && s.includes(alreadyNeedle)) return `${label}: already`;
  const count = (s.match(regex) || []).length;
  if (count !== 1) throw new Error(`${label}: expected 1 regex match, got ${count}`);
  backup(file);
  fs.writeFileSync(file, s.replace(regex, to));
  return `${label}: patched`;
}

function replaceAllRegex(file, regex, to, alreadyNeedle, label) {
  let s = fs.readFileSync(file, 'utf8');
  if (alreadyNeedle && s.includes(alreadyNeedle)) return `${label}: already`;
  const count = (s.match(regex) || []).length;
  if (count < 1) throw new Error(`${label}: expected at least 1 regex match, got ${count}`);
  backup(file);
  fs.writeFileSync(file, s.replace(regex, to));
  return `${label}: patched ${count}`;
}

function replaceLiteralAll(file, pairs, label) {
  let s = fs.readFileSync(file, 'utf8');
  let changed = false;
  for (const [from, to] of pairs) {
    if (s.includes(from)) {
      s = s.split(from).join(to);
      changed = true;
    }
  }
  if (!changed) return `${label}: already`;
  backup(file);
  fs.writeFileSync(file, s);
  return `${label}: patched`;
}

function optionalPatch(fn, label) {
  try {
    return fn();
  } catch (error) {
    return `${label}: skipped (${error.message})`;
  }
}

function insertDescriptor(file, descriptor) {
  let s = fs.readFileSync(file, 'utf8');
  if (s.includes(descriptor)) return 'descriptor g-agent card: already';
  if (s.includes('"g-agent":{id:"g-agent"')) {
    const start = s.indexOf('"g-agent":{id:"g-agent"');
    const end = s.indexOf('custom:{id:"custom",name:"Custom CLI"', start);
    if (end === -1) throw new Error('descriptor g-agent card: could not find custom descriptor after g-agent');
    backup(file);
    fs.writeFileSync(file, `${s.slice(0, start)}${descriptor}${s.slice(end)}`);
    return 'descriptor g-agent card: updated';
  }
  const from = 'custom:{id:"custom",name:"Custom CLI"';
  const count = s.split(from).length - 1;
  if (count !== 1) throw new Error(`descriptor g-agent card: expected 1 match, got ${count}`);
  backup(file);
  fs.writeFileSync(file, s.replace(from, `${descriptor}${from}`));
  return 'descriptor g-agent card: patched';
}

const staticDir = path.join(app, '.next/static/chunks');
const serverDir = path.join(app, '.next/server');
const page = firstFile(path.join(staticDir, 'app/(dashboard)/dashboard/cli-tools'), (f, s) =>
  /page-.*\.js$/.test(f) &&
  s.includes('toolId') &&
  s.includes('modelSelector') &&
  s.includes('eo=["continue","opencode","qwen"')
);
const descriptors = firstFile(staticDir, (f, s) =>
  s.includes('custom:{id:"custom",name:"Custom CLI"') &&
  (s.includes('qwen:{id:"qwen"') || s.includes('hermes:{id:"hermes"'))
);
const runtimeChunk = firstFile(path.join(serverDir, 'chunks'), (f, s) =>
  s.includes('XH:()=>Q') && s.includes('qwen:{defaultCommand:"qwen"') && s.includes('MG:()=>O')
);
const queueDefaultsChunks = matchingFiles(path.join(serverDir, 'chunks'), (f, s) =>
  s.includes('requestsPerMinute:100') && s.includes('minTimeBetweenRequests:200') && s.includes('concurrentRequests:10')
);
const statusRoute = path.join(serverDir, 'app/api/cli-tools/status/route.js');
const guideRoute = path.join(serverDir, 'app/api/cli-tools/guide-settings/[toolId]/route.js');
const middlewareFile = path.join(serverDir, 'middleware.js');
const modelListRoute = path.join(serverDir, 'app/api/models/route.js');
const modelPickerChunks = matchingFiles(staticDir, (f, s) =>
  s.includes('modelAliases:b={}') &&
  s.includes('children:[n&&(0,t.jsx)("span"') &&
  s.includes('onClick:()=>D(e)')
);
const imageCatalogChunks = matchingFiles(path.join(serverDir, 'chunks'), (f, s) =>
  s.includes('format:"codex-responses"') &&
  s.includes('function j(){let a=[];for(let[b,c]of Object.entries(g))')
);

const results = [];

if (queueDefaultsChunks.length > 0) {
  for (const queueDefaultsChunk of queueDefaultsChunks) {
    results.push(replaceAllRegex(
      queueDefaultsChunk,
      /([A-Za-z_$][\w$]*)=\{requestsPerMinute:100,minTimeBetweenRequests:200,concurrentRequests:10\}/g,
      '$1={requestsPerMinute:9999,minTimeBetweenRequests:0,concurrentRequests:64}',
      'requestsPerMinute:9999,minTimeBetweenRequests:0,concurrentRequests:64',
      `server queue defaults (${path.basename(queueDefaultsChunk)})`
    ));
  }
} else if (matchingFiles(path.join(serverDir, 'chunks'), (f, s) => s.includes('requestsPerMinute:9999,minTimeBetweenRequests:0,concurrentRequests:64')).length > 0) {
  results.push('server queue defaults: already');
} else {
  throw new Error('server queue defaults: could not find default queue settings');
}

const modelResolverChunks = matchingFiles(path.join(serverDir, 'chunks'), (f, s) =>
  s.includes('gemini-cli') && (
    s.includes('"gemini-3.1-pro-preview":"gemini-3.1-pro"') ||
    s.includes('claude-opus-4-5-20251101')
  )
);
if (modelResolverChunks.length > 0) {
  for (const chunk of modelResolverChunks) {
    results.push(replaceLiteralAll(chunk, [
      [
        'github:{"claude-4.5-opus":"claude-opus-4-5-20251101","claude-opus-4.5":"claude-opus-4-5-20251101","gemini-3-pro":"gemini-3.1-pro-preview","gemini-3-pro-preview":"gemini-3.1-pro-preview","gemini-3-flash":"gemini-3-flash-preview","raptor-mini":"oswe-vscode-prime"}',
        'github:{"claude-4.5-opus":"claude-opus-4.5","claude-opus-4.5":"claude-opus-4.5","gemini-3-pro":"gemini-3.1-pro-preview","gemini-3-pro-preview":"gemini-3.1-pro-preview","gemini-3-flash":"gemini-3-flash-preview","raptor-mini":"oswe-vscode-prime"}'
      ],
      [
        'gemini:{"gemini-3.1-pro-preview":"gemini-3.1-pro","gemini-3-1-pro":"gemini-3.1-pro"}',
        'gemini:{"gemini-3-1-pro":"gemini-3.1-pro-preview"}'
      ],
      [
        '"gemini-cli":{"gemini-3.1-pro-preview":"gemini-3.1-pro","gemini-3-1-pro":"gemini-3.1-pro"}',
        '"gemini-cli":{"gemini-3-1-pro":"gemini-3.1-pro-preview"}'
      ],
      ['"claude-opus-4.5":"claude-opus-4-5-20251101"', '"claude-opus-4.5":"claude-opus-4.5"'],
      ['"anthropic/claude-opus-4.5":"claude-opus-4-5-20251101"', '"anthropic/claude-opus-4.5":"anthropic/claude-opus-4.5"'],
    ], `model resolver compat cleanup (${path.basename(chunk)})`));
  }
} else {
  results.push('model resolver compat cleanup: already');
}

const aliasStoreChunks = matchingFiles(path.join(serverDir, 'chunks'), (f, s) =>
  s.includes("INSERT OR REPLACE INTO key_value (namespace, key, value) VALUES ('modelAliases', ?, ?)")
);
if (aliasStoreChunks.length > 0) {
  for (const chunk of aliasStoreChunks) {
    results.push(replaceLiteralAll(chunk, [
      [
        "async function u(a,b){(0,d.sm)().prepare(\"INSERT OR REPLACE INTO key_value (namespace, key, value) VALUES ('modelAliases', ?, ?)\").run(a,JSON.stringify(b)),(0,e.lR)(\"pre-write\")}",
        "async function u(a,b){if(\"string\"==typeof a&&/^(claude|gpt|gemini|o[0-9])/.test(a)&&\"string\"==typeof b&&b.startsWith(\"openrouter/\"))return;(0,d.sm)().prepare(\"INSERT OR REPLACE INTO key_value (namespace, key, value) VALUES ('modelAliases', ?, ?)\").run(a,JSON.stringify(b)),(0,e.lR)(\"pre-write\")}"
      ],
      [
        "async function m(a,b){(0,d.getDbInstance)().prepare(\"INSERT OR REPLACE INTO key_value (namespace, key, value) VALUES ('modelAliases', ?, ?)\").run(a,JSON.stringify(b)),(0,e.lR)(\"pre-write\")}",
        "async function m(a,b){if(\"string\"==typeof a&&/^(claude|gpt|gemini|o[0-9])/.test(a)&&\"string\"==typeof b&&b.startsWith(\"openrouter/\"))return;(0,d.getDbInstance)().prepare(\"INSERT OR REPLACE INTO key_value (namespace, key, value) VALUES ('modelAliases', ?, ?)\").run(a,JSON.stringify(b)),(0,e.lR)(\"pre-write\")}"
      ],
    ], `model alias OpenRouter guard (${path.basename(chunk)})`));
  }
} else {
  results.push('model alias OpenRouter guard: no alias store chunk found');
}

if (fs.existsSync(modelListRoute)) {
  results.push(replaceLiteralAll(modelListRoute, [
    ['fullModel:b,alias:d[b]||a.model', 'fullModel:b,alias:b'],
  ], 'api models canonical alias'));
}

if (modelPickerChunks.length > 0) {
  for (const chunk of modelPickerChunks) {
    results.push(replaceLiteralAll(chunk, [
      [
        '(0,p.ir)(e,{modelId:a.id,modelName:a.name,source:a.source})',
        '(0,p.ir)(e,{modelId:a.id,modelName:a.value||a.name,source:a.source})'
      ],
      [
        'return(0,t.jsxs)("button",{onClick:()=>D(e),className:`',
        'return(0,t.jsxs)("button",{onClick:()=>D(e),title:e.value,className:`'
      ],
      [
        'children:[n&&(0,t.jsx)("span",{className:"mr-0.5 opacity-70",children:"✓"}),e.name,e.source&&',
        'children:[n&&(0,t.jsx)("span",{className:"mr-0.5 opacity-70",children:"✓"}),e.value,e.source&&'
      ],
    ], `model picker canonical labels (${path.basename(chunk)})`));
  }
} else {
  results.push('model picker canonical labels: no picker chunk found');
}

results.push(replaceLiteralAll(middlewareFile, [
  [
    'if(!w.allow){let b;if(o){let b;return(b=g.NextResponse.redirect(new URL("/login",a.url))).cookies.delete("auth_token"),s(b,f,"MANAGEMENT"),(0,k.I5)(b,a),b}',
    'if(!w.allow){let b;if(o&&d==="/dashboard/onboarding"){let b=g.NextResponse.next({request:{headers:q}});return b.headers.set(p.jJ,f),b.headers.set(p.S2,m.routeClass),(0,k.I5)(b,a),b}if(o){let b;return(b=g.NextResponse.redirect(new URL("/login",a.url))).cookies.delete("auth_token"),s(b,f,"MANAGEMENT"),(0,k.I5)(b,a),b}'
  ],
], 'middleware onboarding bootstrap access'));

if (imageCatalogChunks.length > 0) {
  for (const chunk of imageCatalogChunks) {
    results.push(replaceLiteralAll(chunk, [
      [
        'models:[{id:"gpt-image-2",name:"GPT Image 2"},{id:"gpt-image-1.5",name:"GPT Image 1.5"},{id:"gpt-image-1",name:"GPT Image 1"},{id:"gpt-image-1-mini",name:"GPT Image 1 Mini"},{id:"chatgpt-image-latest",name:"ChatGPT Image Latest"}]',
        'models:[{id:"gpt-5.5",name:"GPT 5.5 (Codex Image)"},{id:"gpt-5.4",name:"GPT 5.4 (Codex Image)"},{id:"gpt-5.3-codex",name:"GPT 5.3 Codex (Image)"}]'
      ],
      [
        'function j(){let a=[];for(let[b,c]of Object.entries(g))for(let d of c.models)a.push({id:`${b}/${d.id}`,name:d.name,provider:b,supportedSizes:c.supportedSizes,inputModalities:d.inputModalities||["text"],description:d.description||void 0});for(let[b,c]of Object.entries(d)){',
        'function j(){let a=[];for(let[b,c]of Object.entries(g)){let e=c.alias||b;for(let d of c.models)a.push({id:`${e}/${d.id}`,name:d.name,provider:b,supportedSizes:c.supportedSizes,inputModalities:d.inputModalities||["text"],description:d.description||void 0})}for(let[b,c]of Object.entries(d)){'
      ],
    ], `image catalog codex/canonical labels (${path.basename(chunk)})`));
  }
} else {
  results.push('image catalog codex/canonical labels: no image catalog chunk found');
}

results.push(replaceRegex(
  runtimeChunk,
  /qwen:\{defaultCommand:"qwen",envBinKey:"CLI_QWEN_BIN",requiresBinary:!0,healthcheckTimeoutMs:12e3,paths:\{settings:"\.qwen\/settings\.json",env:"\.qwen\/\.env"\}\}/,
  '$&,"g-agent":{defaultCommand:"g-agent",envBinKey:"CLI_G_AGENT_BIN",requiresBinary:!0,healthcheckTimeoutMs:12e3,paths:{config:".g-agent/config.json"}}',
  '"g-agent":{defaultCommand:"g-agent"',
  'runtime g-agent registration'
));
results.push(replaceLiteralAll(runtimeChunk, [
  [
    'hermes:{defaultCommand:"hermes",envBinKey:"CLI_HERMES_BIN",requiresBinary:!1,healthcheckTimeoutMs:4e3,paths:{config:".config/hermes/config.json"}}',
    'hermes:{defaultCommand:"hermes",envBinKey:"CLI_HERMES_BIN",requiresBinary:!0,healthcheckTimeoutMs:12e3,paths:{config:".hermes/config.yaml"}}'
  ],
  [
    'hermes:{defaultCommand:"hermes",envBinKey:"CLI_HERMES_BIN",requiresBinary:!0,healthcheckTimeoutMs:4e3,paths:{config:".config/hermes/config.json"}}',
    'hermes:{defaultCommand:"hermes",envBinKey:"CLI_HERMES_BIN",requiresBinary:!0,healthcheckTimeoutMs:12e3,paths:{config:".hermes/config.yaml"}}'
  ],
  [
    'hermes:{defaultCommand:"hermes",envBinKey:"CLI_HERMES_BIN",requiresBinary:!1,healthcheckTimeoutMs:12e3,paths:{config:".config/hermes/config.json"}}',
    'hermes:{defaultCommand:"hermes",envBinKey:"CLI_HERMES_BIN",requiresBinary:!0,healthcheckTimeoutMs:12e3,paths:{config:".hermes/config.yaml"}}'
  ],
], 'runtime hermes config path'));

results.push(replaceOnce(
  statusRoute,
  'case"droid":case"openclaw":case"cline":case"kilo":let g=JSON.stringify(d).toLowerCase();',
  'case"droid":case"openclaw":case"cline":case"kilo":case"g-agent":let g=JSON.stringify(d).toLowerCase();',
  'status config detection switch'
));
results.push(replaceOnce(
  statusRoute,
  '["claude","codex","droid","openclaw","cline","kilo","qwen"].map',
  '["claude","codex","droid","openclaw","cline","kilo","qwen","g-agent"].map',
  'status config detection list'
));

const gAgentDescriptor = [
  '"g-agent":{id:"g-agent",name:"G-Agent",image:"/providers/g-agent.webp",color:"#9B00FF",description:"G-Agent CLI configured through OmniRoute proxy. First selected model is primary; the rest are saved as fallback models. Image model is saved to visual.imageGen.",docsUrl:"/docs?section=cli-tools&tool=g-agent",configType:"guide",defaultCommand:"g-agent",modelSelectionMode:"multiple",guideSteps:[{step:1,title:"Install G-Agent",desc:"Use your existing g-agent binary or install it into PATH."},{step:2,title:"API Key",type:"apiKeySelector"},{step:3,title:"Base URL",value:"{{baseUrl}}",copyable:!0},{step:4,title:"Primary + Fallback + Image Models",type:"modelSelector"},{step:5,title:"Save Config",desc:"Click Save Config below to update ~/.g-agent/config.json. Chat models are saved under agents.defaults; the image model is saved under visual.imageGen."}],codeBlock:{language:"json",code:`{\\n  "providers": {\\n    "proxy": {\\n      "type": "openai-compatible",\\n      "apiBase": "{{baseUrl}}",\\n      "apiKey": "{{apiKey}}"\\n    }\\n  },\\n  "agents": {\\n    "defaults": {\\n      "model": "{{model}}",\\n      "routing": {\\n        "mode": "proxy",\\n        "proxyProvider": "proxy",\\n        "fallbackModels": {{fallbackModelsJson}}\\n      }\\n    }\\n  },\\n  "visual": {\\n    "enabled": true,\\n    "imageGen": {\\n      "provider": "openai-compatible",\\n      "apiBase": "{{baseUrl}}",\\n      "apiKey": "{{apiKey}}",\\n      "model": "{{imageModel}}",\\n      "timeout": 180\\n    }\\n  }\\n}`}},'
].join('');
const descriptorTargets = [
  descriptors,
  ...matchingFiles(path.join(serverDir, 'chunks'), (f, s) =>
    s.includes('hermes:{id:"hermes"') && s.includes('custom:{id:"custom"')
  ),
].filter((f, idx, arr) => arr.indexOf(f) === idx);
for (const descriptorTarget of descriptorTargets) {
  results.push(insertDescriptor(descriptorTarget, gAgentDescriptor));
  results.push(replaceRegex(
    descriptorTarget,
    /hermes:\{id:"hermes",name:"Hermes"[\s\S]*?\}\},amp:\{id:"amp"/,
    'hermes:{id:"hermes",name:"Hermes",icon:"terminal",color:"#8B5CF6",description:"Hermes AI Terminal Assistant configured through OmniRoute proxy",docsUrl:"/docs?section=cli-tools&tool=hermes",configType:"guide",defaultCommand:"hermes",guideSteps:[{step:1,title:"Open Hermes Config",desc:"OmniRoute saves directly to ~/.hermes/config.yaml for this local Hermes install."},{step:2,title:"API Key",type:"apiKeySelector"},{step:3,title:"Base URL",value:"{{baseUrl}}",copyable:!0},{step:4,title:"Select Model",type:"modelSelector"},{step:5,title:"Save Config",desc:"Click Save Config below to update ~/.hermes/config.yaml. Only model.default, provider, base_url, api_key env reference, and api_mode are changed."}],codeBlock:{language:"yaml",code:"model:\\n  default: {{model}}\\n  provider: custom\\n  base_url: {{baseUrl}}\\n  api_key: ${OMNIROUTE_API_KEY}\\n  api_mode: chat_completions"}},amp:{id:"amp"',
    'api_key: ${OMNIROUTE_API_KEY}',
    'descriptor hermes direct save'
  ));
}
results.push(replaceLiteralAll(page, [
  [
    'P=new Set(["cursor","windsurf","continue","opencode","hermes","amp","qwen"])',
    'P=new Set(["cursor","windsurf","continue","opencode","hermes","amp","qwen","g-agent"])'
  ],
  [
    'T=new Set(["cursor","windsurf","continue","opencode","hermes","amp","qwen"])',
    'T=new Set(["cursor","windsurf","continue","opencode","hermes","amp","qwen","g-agent"])'
  ],
], 'page guided category'));
if (fs.readFileSync(page, 'utf8').includes('eo=["continue","opencode","qwen","hermes","g-agent"].includes(e)')) {
  results.push('page save-enabled tools: already');
} else if (fs.readFileSync(page, 'utf8').includes('eo=["continue","opencode","qwen","g-agent"].includes(e)')) {
  results.push(replaceOnce(
    page,
    'eo=["continue","opencode","qwen","g-agent"].includes(e)',
    'eo=["continue","opencode","qwen","hermes","g-agent"].includes(e)',
    'page hermes save-enabled tools'
  ));
} else {
  results.push(replaceOnce(
    page,
    'eo=["continue","opencode","qwen"].includes(e)',
    'eo=["continue","opencode","qwen","hermes","g-agent"].includes(e)',
    'page save-enabled tools'
  ));
}
results.push(replaceOnce(
  page,
  'b=(0,a.useCallback)((e,t,s)=>{try{return f(e,s)}catch{return t}},[f])',
  'b=(0,a.useCallback)((e,t,s)=>{try{let l=f(e,s);return l===e||l===`cliTools.${e}`?t:l}catch{return t}},[f])',
  'page guide translation fallback'
));
results.push(optionalPatch(() => replaceOnce(
  page,
  'return e.replace(/\\{\\{baseUrl\\}\\}/g,V).replace(/\\{\\{apiKey\\}\\}/g,t).replace(/\\{\\{model\\}\\}/g,q()[0]||f("modelPlaceholder"))',
  'return e.replace(/\\{\\{baseUrl\\}\\}/g,V).replace(/\\{\\{apiKey\\}\\}/g,t).replace(/\\{\\{model\\}\\}/g,q()[0]||f("modelPlaceholder")).replace(/\\{\\{fallbackModelsJson\\}\\}/g,JSON.stringify((B?el().slice(1):[]),null,8))',
  'page fallbackModelsJson template'
), 'page fallbackModelsJson template'));
results.push(optionalPatch(() => replaceOnce(
  page,
  '[M,K]=(0,a.useState)(!1),D=(0,a.useRef)(!1)',
  '[M,K]=(0,a.useState)(!1),[imageModel,setImageModel]=(0,a.useState)("cx/gpt-5.5"),D=(0,a.useRef)(!1)',
  'page g-agent image model state'
), 'page g-agent image model state'));
results.push(optionalPatch(() => replaceOnce(
  page,
  'else $(t);let s=localStorage.getItem(`omniroute-cli-key-${e}`);',
  'else $(t);if("g-agent"===e){let i=localStorage.getItem(`omniroute-cli-image-model-${e}`);i&&setImageModel(i)}let s=localStorage.getItem(`omniroute-cli-key-${e}`);',
  'page g-agent image model localStorage load'
), 'page g-agent image model localStorage load'));
results.push(optionalPatch(() => replaceOnce(
  page,
  '.replace(/\\{\\{fallbackModelsJson\\}\\}/g,JSON.stringify((B?el().slice(1):[]),null,8))},[n,q,W,f])',
  '.replace(/\\{\\{fallbackModelsJson\\}\\}/g,JSON.stringify((B?el().slice(1):[]),null,8)).replace(/\\{\\{imageModel\\}\\}/g,imageModel||"cx/gpt-5.5")},[n,q,W,f,imageModel])',
  'page g-agent image model template'
), 'page g-agent image model template'));
results.push(optionalPatch(() => replaceOnce(
  page,
  'body:JSON.stringify({baseUrl:V,apiKey:m?null:"sk_omniroute",keyId:t,model:A,models:B?el():void 0,modelLabels:Z()})',
  'body:JSON.stringify({baseUrl:V,apiKey:m?null:"sk_omniroute",keyId:t,model:A,models:B?el():void 0,modelLabels:Z(),imageModel:"g-agent"===e?imageModel:void 0})',
  'page g-agent image model save payload'
), 'page g-agent image model save payload'));

const oldModelSelector = '"modelSelector"===s.type&&(a=B?q().join(", "):q()[0]||"",(0,l.jsxs)("div",{className:"mt-2 flex items-center gap-2",children:[(0,l.jsx)("input",{type:"text",value:a,onChange:e=>B?X(e.target.value.split(",").map(e=>e.trim()).filter(Boolean)):Q(e.target.value),placeholder:f("modelPlaceholder"),className:"flex-1 px-3 py-2 bg-bg-secondary rounded-lg text-sm border border-border focus:outline-none focus:ring-1 focus:ring-primary/50"}),(0,l.jsx)("button",{onClick:()=>O(!0),disabled:!er,className:`shrink-0 px-3 py-2 rounded-lg border text-sm transition-colors ${er?"bg-bg-secondary border-border text-text-main hover:border-primary cursor-pointer":"opacity-50 cursor-not-allowed border-border"}`,children:f("selectModel")}),a&&(0,l.jsxs)(l.Fragment,{children:[(0,l.jsx)("button",{onClick:()=>es(a,"model"),className:"shrink-0 px-3 py-2 bg-bg-secondary hover:bg-bg-tertiary rounded-lg border border-border transition-colors",children:(0,l.jsx)("span",{className:"material-symbols-outlined text-lg",children:"model"===C?"check":"content_copy"})}),(0,l.jsx)("button",{onClick:()=>B?X([]):Q(""),className:"p-2 text-text-muted hover:text-red-500 rounded transition-colors",title:f("clear"),children:(0,l.jsx)("span",{className:"material-symbols-outlined text-lg",children:"close"})})]})]}))';
const newModelSelector = '"modelSelector"===s.type&&(a=B?q().join(", "):q()[0]||"","g-agent"===e?(0,l.jsxs)("div",{className:"mt-2 flex flex-col gap-3",children:[(0,l.jsxs)("div",{className:"flex flex-col gap-1.5",children:[(0,l.jsx)("label",{className:"text-xs font-medium text-text-muted",children:"Primary model"}),(0,l.jsxs)("div",{className:"flex items-center gap-2",children:[(0,l.jsx)("input",{type:"text",value:A,onChange:e=>{let t=e.target.value.trim();X([t,...E.filter(e=>e&&e!==A&&e!==t)].filter(Boolean))},placeholder:f("modelPlaceholder"),className:"flex-1 px-3 py-2 bg-bg-secondary rounded-lg text-sm border border-border focus:outline-none focus:ring-1 focus:ring-primary/50"}),(0,l.jsx)("button",{onClick:()=>O(!0),disabled:!er,className:`shrink-0 px-3 py-2 rounded-lg border text-sm transition-colors ${er?"bg-bg-secondary border-border text-text-main hover:border-primary cursor-pointer":"opacity-50 cursor-not-allowed border-border"}`,children:"Select models"})]})]}),(0,l.jsxs)("div",{className:"flex flex-col gap-1.5",children:[(0,l.jsxs)("div",{className:"flex items-center justify-between gap-2",children:[(0,l.jsx)("label",{className:"text-xs font-medium text-text-muted",children:"Fallback models"}),(0,l.jsx)("span",{className:"text-[11px] text-text-muted",children:`${Math.max(0,E.filter(e=>e&&e!==A).length)} selected`})]}),(0,l.jsx)("textarea",{value:E.filter(e=>e&&e!==A).join("\\n"),onChange:e=>{let t=e.target.value.split(/[,\\n]/).map(e=>e.trim()).filter(Boolean);X([A,...t].filter(Boolean))},placeholder:"one fallback model per line",rows:Math.max(3,Math.min(10,E.filter(e=>e&&e!==A).length+1)),className:"w-full px-3 py-2 bg-bg-secondary rounded-lg text-sm border border-border focus:outline-none focus:ring-1 focus:ring-primary/50 font-mono resize-y"}),E.filter(e=>e&&e!==A).length>0&&(0,l.jsx)("div",{className:"flex flex-wrap gap-1.5",children:E.filter(e=>e&&e!==A).map(e=>(0,l.jsxs)("span",{className:"inline-flex items-center gap-1 px-2 py-1 rounded-md bg-primary/10 text-primary text-xs font-mono",children:[e,(0,l.jsx)("button",{type:"button",onClick:()=>X(E.filter(t=>t!==e)),className:"text-primary/70 hover:text-red-500",children:(0,l.jsx)("span",{className:"material-symbols-outlined text-[12px]",children:"close"})})]},e))})]}),(0,l.jsxs)("div",{className:"flex items-center gap-2",children:[(0,l.jsx)("button",{onClick:()=>es(a,"model"),disabled:!a,className:"shrink-0 px-3 py-2 bg-bg-secondary hover:bg-bg-tertiary rounded-lg border border-border transition-colors disabled:opacity-50",children:(0,l.jsx)("span",{className:"material-symbols-outlined text-lg",children:"model"===C?"check":"content_copy"})}),(0,l.jsx)("button",{onClick:()=>X([]),className:"px-3 py-2 text-text-muted hover:text-red-500 rounded-lg border border-border transition-colors",children:f("clear")})]})]}):(0,l.jsxs)("div",{className:"mt-2 flex items-center gap-2",children:[(0,l.jsx)("input",{type:"text",value:a,onChange:e=>B?X(e.target.value.split(",").map(e=>e.trim()).filter(Boolean)):Q(e.target.value),placeholder:f("modelPlaceholder"),className:"flex-1 px-3 py-2 bg-bg-secondary rounded-lg text-sm border border-border focus:outline-none focus:ring-1 focus:ring-primary/50"}),(0,l.jsx)("button",{onClick:()=>O(!0),disabled:!er,className:`shrink-0 px-3 py-2 rounded-lg border text-sm transition-colors ${er?"bg-bg-secondary border-border text-text-main hover:border-primary cursor-pointer":"opacity-50 cursor-not-allowed border-border"}`,children:f("selectModel")}),a&&(0,l.jsxs)(l.Fragment,{children:[(0,l.jsx)("button",{onClick:()=>es(a,"model"),className:"shrink-0 px-3 py-2 bg-bg-secondary hover:bg-bg-tertiary rounded-lg border border-border transition-colors",children:(0,l.jsx)("span",{className:"material-symbols-outlined text-lg",children:"model"===C?"check":"content_copy"})}),(0,l.jsx)("button",{onClick:()=>B?X([]):Q(""),className:"p-2 text-text-muted hover:text-red-500 rounded transition-colors",title:f("clear"),children:(0,l.jsx)("span",{className:"material-symbols-outlined text-lg",children:"close"})})]})]}))';
if (fs.readFileSync(page, 'utf8').includes('children:"Fallback models"')) {
  results.push('page g-agent primary/fallback UI: already');
} else {
  results.push(optionalPatch(
    () => replaceOnce(page, oldModelSelector, newModelSelector, 'page g-agent primary/fallback UI'),
    'page g-agent primary/fallback UI'
  ));
}
const imageModelControls = '(0,l.jsxs)("div",{className:"flex flex-col gap-1.5",children:[(0,l.jsx)("label",{className:"text-xs font-medium text-text-muted",children:"Image model"}),(0,l.jsxs)("div",{className:"flex items-center gap-2",children:[(0,l.jsxs)("select",{value:imageModel,onChange:s=>{let t=s.target.value;setImageModel(t),t?localStorage.setItem(`omniroute-cli-image-model-${e}`,t):localStorage.removeItem(`omniroute-cli-image-model-${e}`)},className:"min-w-0 flex-1 px-3 py-2 bg-bg-secondary rounded-lg text-sm border border-border focus:outline-none focus:ring-1 focus:ring-primary/50 font-mono",children:[!["cx/gpt-5.5","cx/gpt-5.4","cx/gpt-5.3-codex"].includes(imageModel)&&imageModel&&(0,l.jsx)("option",{value:imageModel,children:imageModel}),["cx/gpt-5.5","cx/gpt-5.4","cx/gpt-5.3-codex"].map(e=>(0,l.jsx)("option",{value:e,children:e},e))]}),(0,l.jsx)("input",{type:"text",value:imageModel,onChange:s=>{let t=s.target.value.trim();setImageModel(t),t?localStorage.setItem(`omniroute-cli-image-model-${e}`,t):localStorage.removeItem(`omniroute-cli-image-model-${e}`)},placeholder:"cx/gpt-5.5",className:"min-w-0 flex-1 px-3 py-2 bg-bg-secondary rounded-lg text-sm border border-border focus:outline-none focus:ring-1 focus:ring-primary/50 font-mono"}),(0,l.jsx)("button",{onClick:()=>es(imageModel,"imageModel"),disabled:!imageModel,className:"shrink-0 px-3 py-2 bg-bg-secondary hover:bg-bg-tertiary rounded-lg border border-border transition-colors disabled:opacity-50",children:(0,l.jsx)("span",{className:"material-symbols-outlined text-lg",children:"imageModel"===C?"check":"content_copy"})})]})]})';
results.push(optionalPatch(() => replaceOnce(
  page,
  '})]}),(0,l.jsxs)("div",{className:"flex items-center gap-2",children:[(0,l.jsx)("button",{onClick:()=>es(a,"model"),disabled:!a,className:"shrink-0 px-3 py-2 bg-bg-secondary hover:bg-bg-tertiary rounded-lg border border-border transition-colors disabled:opacity-50"',
  `})]}),${imageModelControls},(0,l.jsxs)("div",{className:"flex items-center gap-2",children:[(0,l.jsx)("button",{onClick:()=>es(a,"model"),disabled:!a,className:"shrink-0 px-3 py-2 bg-bg-secondary hover:bg-bg-tertiary rounded-lg border border-border transition-colors disabled:opacity-50"`,
  'page g-agent image model UI'
), 'page g-agent image model UI'));

if (fs.readFileSync(guideRoute, 'utf8').includes('case"g-agent":return await x({baseUrl:h,apiKey:n,model:i,models:j,imageModel});')) {
  results.push('guide g-agent save switch: already');
} else {
  results.push(replaceOnce(
    guideRoute,
    'case"qwen":return await w({baseUrl:h,apiKey:n,model:i});default:return e.NextResponse.json({error:`Direct config save not supported for: ${f}`},{status:400})',
    'case"qwen":return await w({baseUrl:h,apiKey:n,model:i});case"g-agent":return await x({baseUrl:h,apiKey:n,model:i,models:j});default:return e.NextResponse.json({error:`Direct config save not supported for: ${f}`},{status:400})',
    'guide g-agent save switch'
  ));
}
results.push(replaceOnce(
  guideRoute,
  'let{baseUrl:h,model:i,models:j,modelLabels:k}=g.data,m="string"==typeof c?.keyId?c.keyId.trim():null',
  'let{baseUrl:h,model:i,models:j,modelLabels:k}=g.data,imageModel="string"==typeof c?.imageModel?c.imageModel.trim():"",m="string"==typeof c?.keyId?c.keyId.trim():null',
  'guide g-agent image model request parse'
));
results.push(replaceOnce(
  guideRoute,
  'case"g-agent":return await x({baseUrl:h,apiKey:n,model:i,models:j});',
  'case"g-agent":return await x({baseUrl:h,apiKey:n,model:i,models:j,imageModel});',
  'guide g-agent image model save switch'
));
if (fs.readFileSync(guideRoute, 'utf8').includes('case"hermes":return await saveHermesConfig({baseUrl:h,apiKey:n,model:i});')) {
  results.push('guide hermes save switch: already');
} else if (fs.readFileSync(guideRoute, 'utf8').includes('case"qwen":return await w({baseUrl:h,apiKey:n,model:i});case"g-agent":')) {
  results.push(replaceOnce(
    guideRoute,
    'case"qwen":return await w({baseUrl:h,apiKey:n,model:i});case"g-agent":',
    'case"hermes":return await saveHermesConfig({baseUrl:h,apiKey:n,model:i});case"qwen":return await w({baseUrl:h,apiKey:n,model:i});case"g-agent":',
    'guide hermes save switch'
  ));
} else {
  results.push(replaceOnce(
    guideRoute,
    'case"qwen":return await w({baseUrl:h,apiKey:n,model:i});',
    'case"hermes":return await saveHermesConfig({baseUrl:h,apiKey:n,model:i});case"qwen":return await w({baseUrl:h,apiKey:n,model:i});',
    'guide hermes save switch'
  ));
}

const qwenWriter = 'async function w({baseUrl:a,apiKey:b,model:c}){let d=k().homedir(),f=i().join(d,".qwen","settings.json");await g().mkdir(i().dirname(f),{recursive:!0});let h=String(a||"").trim().replace(/\\/+$/,""),j={};try{let a=await g().readFile(f,"utf-8");j=JSON.parse(a)}catch{}return j.security={...j.security,auth:{selectedType:"openai",apiKey:b||"sk_omniroute",baseUrl:h}},j.model={...j.model,name:c||"gemini-cli/gemini-3.1-pro-preview"},await g().writeFile(f,JSON.stringify(j,null,2),"utf-8"),e.NextResponse.json({success:!0,message:`Qwen Code config saved to ${f}`,configPath:f})}';
const hermesWriter = 'async function saveHermesConfig({baseUrl:a,apiKey:b,model:c}){let d=k().homedir(),f=i().join(d,".hermes","config.yaml");await g().mkdir(i().dirname(f),{recursive:!0});let h=String(a||"").trim().replace(/\\/+$/,""),j=h.endsWith("/v1")?h:h+"/v1",l=String(c||"cx/gpt-5.5-xhigh").trim(),m="${OMNIROUTE_API_KEY}",n="";try{n=await g().readFile(f,"utf-8")}catch{}let o="model:\\n  default: "+l+"\\n  provider: custom\\n  base_url: "+j+"\\n  api_key: "+m+"\\n  api_mode: chat_completions\\n";return /^model:\\n(?:[ \\t].*\\n?)*/m.test(n)?n=n.replace(/^model:\\n(?:[ \\t].*\\n?)*/m,o):n=o+(n?n.startsWith("\\n")?n:"\\n"+n:""),await g().writeFile(f,n,"utf-8"),e.NextResponse.json({success:!0,message:"Hermes config saved to "+f+" using OMNIROUTE_API_KEY env",configPath:f,model:l,baseUrl:j,keyEnv:"OMNIROUTE_API_KEY"})}';
if (fs.readFileSync(guideRoute, 'utf8').includes('async function saveHermesConfig') && !fs.readFileSync(guideRoute, 'utf8').includes('keyEnv:"OMNIROUTE_API_KEY"')) {
  results.push(replaceRegex(
    guideRoute,
    /async function saveHermesConfig[\s\S]*?}async function x\(/,
    hermesWriter + 'async function x(',
    'keyEnv:"OMNIROUTE_API_KEY"',
    'guide hermes config writer env placeholder'
  ));
} else if (fs.readFileSync(guideRoute, 'utf8').includes('async function saveHermesConfig')) {
  results.push('guide hermes config writer: already');
} else {
  results.push(replaceOnce(guideRoute, qwenWriter, qwenWriter + hermesWriter, 'guide hermes config writer'));
}

const oldGAgentWriter = `async function x({baseUrl:a,apiKey:b,model:c,models:d}){let f=k().homedir(),h=i().join(f,".g-agent","config.json");await g().mkdir(i().dirname(h),{recursive:!0});let j=String(a||"").trim().replace(/\\/+$/,""),l={};try{let a=await g().readFile(h,"utf-8");l=JSON.parse(a)}catch{}let m=j.endsWith("/v1")?j:\`${'${j}'}/v1\`,n=Array.isArray(d)?[...new Set(d.map(a=>String(a||"").trim()).filter(Boolean))]:[],o=String(c||n[0]||"hermes-4-70b").trim(),p=n.filter(a=>a&&a!==o);return l.providers={...l.providers,proxy:{...l.providers?.proxy,type:"openai-compatible",apiBase:m,apiKey:b||"sk_omniroute"}},l.agents={...l.agents,defaults:{...l.agents?.defaults,model:o,routing:{...l.agents?.defaults?.routing,mode:"proxy",proxyProvider:"proxy",fallbackModels:p}}},await g().writeFile(h,JSON.stringify(l,null,2),"utf-8"),e.NextResponse.json({success:!0,message:\`G-Agent config saved to ${'${h}'}\`,configPath:h,primaryModel:o,fallbackModels:p})}`;
const newGAgentWriter = `async function x({baseUrl:a,apiKey:b,model:c,models:d,imageModel:q}){let f=k().homedir(),h=i().join(f,".g-agent","config.json");await g().mkdir(i().dirname(h),{recursive:!0});let j=String(a||"").trim().replace(/\\/+$/,""),l={};try{let a=await g().readFile(h,"utf-8");l=JSON.parse(a)}catch{}let m=j.endsWith("/v1")?j:\`${'${j}'}/v1\`,n=Array.isArray(d)?[...new Set(d.map(a=>String(a||"").trim()).filter(Boolean))]:[],o=String(c||n[0]||"hermes-4-70b").trim(),p=n.filter(a=>a&&a!==o);return q=String(q||"").trim(),l.providers={...l.providers,proxy:{...l.providers?.proxy,type:"openai-compatible",apiBase:m,apiKey:b||"sk_omniroute"}},l.agents={...l.agents,defaults:{...l.agents?.defaults,model:o,routing:{...l.agents?.defaults?.routing,mode:"proxy",proxyProvider:"proxy",fallbackModels:p}}},q&&(l.visual={...l.visual,enabled:!0,imageGen:{...l.visual?.imageGen,provider:"openai-compatible",apiBase:m,apiKey:b||"sk_omniroute",model:q,timeout:l.visual?.imageGen?.timeout||180}}),await g().writeFile(h,JSON.stringify(l,null,2),"utf-8"),e.NextResponse.json({success:!0,message:\`G-Agent config saved to ${'${h}'}\`,configPath:h,primaryModel:o,fallbackModels:p,imageModel:q||null})}`;
if (fs.readFileSync(guideRoute, 'utf8').includes(oldGAgentWriter)) {
  results.push(replaceOnce(guideRoute, oldGAgentWriter, newGAgentWriter, 'guide g-agent image config writer'));
} else if (fs.readFileSync(guideRoute, 'utf8').includes(newGAgentWriter)) {
  results.push('guide g-agent config writer: already');
} else {
  results.push(replaceOnce(guideRoute, qwenWriter, `${qwenWriter}${newGAgentWriter}`, 'guide g-agent config writer'));
}

for (const f of [page, ...descriptorTargets, runtimeChunk, ...queueDefaultsChunks, statusRoute, guideRoute, modelListRoute, ...modelPickerChunks, ...imageCatalogChunks]) {
  new Function(fs.readFileSync(f, 'utf8'));
}

console.log(results.join('\n'));
console.log(`page=${page}`);
console.log(`descriptors=${descriptors}`);
console.log(`runtimeChunk=${runtimeChunk}`);
console.log(`queueDefaultsChunks=${queueDefaultsChunks.join(',') || 'already'}`);
NODE

if command -v sqlite3 >/dev/null 2>&1 && [[ -f "$DB_FILE" ]]; then
  printf 'Applying strict model alias cleanup in %s...\n' "$DB_FILE"
  sqlite3 "$DB_FILE" <<'SQL'
CREATE TABLE IF NOT EXISTS alias_quarantine (
  key TEXT,
  value TEXT,
  reason TEXT,
  quarantined_at TEXT DEFAULT (datetime('now'))
);
INSERT INTO alias_quarantine(key,value,reason)
SELECT key,value,'strict-clean: removed short OpenRouter alias for claude/gpt/gemini/o families'
FROM key_value
WHERE namespace='modelAliases'
  AND json_valid(value)=1
  AND json_type(value)='text'
  AND json_extract(value,'$') LIKE 'openrouter/%'
  AND (key GLOB 'claude*' OR key GLOB 'gpt*' OR key GLOB 'gemini*' OR key GLOB 'o[0-9]*');
DELETE FROM key_value
WHERE namespace='modelAliases'
  AND json_valid(value)=1
  AND json_type(value)='text'
  AND json_extract(value,'$') LIKE 'openrouter/%'
  AND (key GLOB 'claude*' OR key GLOB 'gpt*' OR key GLOB 'gemini*' OR key GLOB 'o[0-9]*');
INSERT OR REPLACE INTO key_value(namespace,key,value) VALUES
('modelAliases','claude-haiku-4.5',json_quote('github/claude-haiku-4.5')),
('modelAliases','claude-sonnet-4',json_quote('github/claude-sonnet-4')),
('modelAliases','claude-sonnet-4.5',json_quote('github/claude-sonnet-4.5')),
('modelAliases','claude-sonnet-4.6',json_quote('github/claude-sonnet-4.6')),
('modelAliases','claude-opus-4.1',json_quote('github/claude-opus-41')),
('modelAliases','claude-opus-41',json_quote('github/claude-opus-41')),
('modelAliases','claude-opus-4.5',json_quote('github/claude-opus-4.5')),
('modelAliases','claude-opus-4.6',json_quote('github/claude-opus-4.6')),
('modelAliases','claude-opus-4.7',json_quote('github/claude-opus-4.7')),
('modelAliases','gpt-4.1',json_quote('cx/gpt-4.1')),
('modelAliases','gpt-4o',json_quote('cx/gpt-4o')),
('modelAliases','gpt-4o-mini',json_quote('cx/gpt-4o-mini')),
('modelAliases','gpt-5',json_quote('cx/gpt-5')),
('modelAliases','gpt-5-mini',json_quote('cx/gpt-5-mini')),
('modelAliases','gpt-5-codex',json_quote('cx/gpt-5-codex')),
('modelAliases','gpt-5.1',json_quote('cx/gpt-5.1')),
('modelAliases','gpt-5.1-codex',json_quote('cx/gpt-5.1-codex')),
('modelAliases','gpt-5.1-codex-max',json_quote('cx/gpt-5.1-codex-max')),
('modelAliases','gpt-5.1-codex-mini',json_quote('cx/gpt-5.1-codex-mini')),
('modelAliases','gpt-5.2',json_quote('cx/gpt-5.2')),
('modelAliases','gpt-5.2-codex',json_quote('cx/gpt-5.2-codex')),
('modelAliases','gpt-5.2-pro',json_quote('cx/gpt-5.2-pro')),
('modelAliases','gpt-5.3-codex',json_quote('cx/gpt-5.3-codex')),
('modelAliases','gpt-5.4',json_quote('cx/gpt-5.4')),
('modelAliases','gpt-5.4-mini',json_quote('cx/gpt-5.4-mini')),
('modelAliases','gpt-5.4-nano',json_quote('cx/gpt-5.4-nano')),
('modelAliases','gpt-5.4-pro',json_quote('cx/gpt-5.4-pro')),
('modelAliases','gpt-5.5',json_quote('cx/gpt-5.5')),
('modelAliases','gpt-5.5-pro',json_quote('cx/gpt-5.5-pro')),
('modelAliases','o1',json_quote('cx/o1')),
('modelAliases','o1-pro',json_quote('cx/o1-pro')),
('modelAliases','o3',json_quote('cx/o3')),
('modelAliases','o3-mini',json_quote('cx/o3-mini')),
('modelAliases','o3-pro',json_quote('cx/o3-pro')),
('modelAliases','o4-mini',json_quote('cx/o4-mini')),
('modelAliases','gemini-2.5-flash',json_quote('gemini-cli/gemini-2.5-flash')),
('modelAliases','gemini-2.5-flash-lite',json_quote('gemini-cli/gemini-2.5-flash-lite')),
('modelAliases','gemini-2.5-pro',json_quote('gemini-cli/gemini-2.5-pro')),
('modelAliases','gemini-3-flash-preview',json_quote('gemini-cli/gemini-3-flash-preview')),
('modelAliases','gemini-3-pro-preview',json_quote('gemini-cli/gemini-3-pro-preview')),
('modelAliases','gemini-3.1-pro',json_quote('gemini-cli/gemini-3.1-pro-preview')),
('modelAliases','gemini-3.1-flash-lite-preview',json_quote('gemini-cli/gemini-3.1-flash-lite-preview')),
('modelAliases','gemini-3.1-pro-preview',json_quote('gemini-cli/gemini-3.1-pro-preview'));
DELETE FROM model_capabilities WHERE provider='cx' AND model_id IN ('gpt-image-2','gpt-image-1.5','gpt-image-1','gpt-image-1-mini','chatgpt-image-latest');
INSERT OR REPLACE INTO model_capabilities (
  provider, model_id, tool_call, reasoning, attachment, structured_output, temperature,
  modalities_input, modalities_output, release_date, last_updated, status, family,
  open_weights, limit_context, limit_input, limit_output, last_synced
) VALUES
('cx','gpt-5.5',1,1,1,NULL,1,'["text","image"]','["text","image"]',NULL,NULL,NULL,'gpt-5',0,0,0,0,datetime('now')),
('cx','gpt-5.4',1,1,1,NULL,1,'["text","image"]','["text","image"]',NULL,NULL,NULL,'gpt-5',0,0,0,0,datetime('now')),
('cx','gpt-5.3-codex',1,1,1,NULL,1,'["text","image"]','["text","image"]',NULL,NULL,NULL,'gpt-5',0,0,0,0,datetime('now'));

UPDATE provider_connections
SET test_status='active',
    last_error=NULL,
    last_error_at=NULL,
    error_code=NULL,
    last_error_type=NULL,
    last_error_source=NULL,
    backoff_level=0,
    rate_limited_until=NULL
WHERE provider IN ('gemini-cli','github') AND test_status IN ('unavailable','credits_exhausted');
SQL
fi

printf 'Restarting %s...\n' "$SERVICE"
systemctl --user restart "$SERVICE"
sleep 2
if command -v sqlite3 >/dev/null 2>&1 && [[ -f "$DB_FILE" ]]; then
  sqlite3 "$DB_FILE" "DELETE FROM model_capabilities WHERE provider='cx' AND model_id IN ('gpt-image-2','gpt-image-1.5','gpt-image-1','gpt-image-1-mini','chatgpt-image-latest');"
fi

printf 'Verifying dashboard and g-agent runtime...\n'
curl -fsS -o /tmp/omniroute-g-agent-logo.webp -w 'logo %{http_code} %{size_download}\n' http://127.0.0.1:20128/providers/g-agent.webp
dashboard_status="$(curl -sS -o /tmp/omniroute-cli-tools.html -w '%{http_code}' http://127.0.0.1:20128/dashboard/cli-tools)"
printf 'dashboard %s\n' "$dashboard_status"
if [[ "$dashboard_status" != "200" && "$dashboard_status" != "307" ]]; then
  printf 'Unexpected dashboard status: %s\n' "$dashboard_status" >&2
  exit 1
fi
if ! grep -R -q '"g-agent":{defaultCommand:"g-agent"' "$APP/.next/server/chunks"; then
  printf 'g-agent runtime patch not found in server chunks\n' >&2
  exit 1
fi
if ! grep -R -q '"g-agent":{id:"g-agent"' "$APP/.next/static/chunks"; then
  printf 'g-agent dashboard descriptor patch not found in static chunks\n' >&2
  exit 1
fi
if ! grep -R -q 'requestsPerMinute:9999,minTimeBetweenRequests:0,concurrentRequests:64' "$APP/.next/server/chunks"; then
  printf 'queue defaults patch not found in server chunks\n' >&2
  exit 1
fi
runtime_status="$(curl -sS -o /tmp/omniroute-g-agent-runtime.json -w '%{http_code}' http://127.0.0.1:20128/api/cli-tools/runtime/g-agent || true)"
if [[ "$runtime_status" == "200" ]]; then
  node -e 'const fs=require("fs");const j=JSON.parse(fs.readFileSync("/tmp/omniroute-g-agent-runtime.json","utf8")); console.log(`g-agent installed=${j.installed} runnable=${j.runnable} path=${j.commandPath||""}`); if(!j.installed||!j.runnable) process.exit(1);'
elif [[ "$runtime_status" == "401" ]]; then
  printf 'g-agent runtime endpoint protected by auth; build patches verified\n'
else
  printf 'Unexpected runtime status: %s\n' "$runtime_status" >&2
  exit 1
fi

printf 'Done. Hard reload http://localhost:20128/dashboard/cli-tools\n'
