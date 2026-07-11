# AI Context Engine

**A pre-commit reasoning layer for AI coding agents.**

> *"We don't make AI smarter. We give AI a memory of your system."*

---

## Does Claude burn through your plan too fast?

If you're using Claude Pro or Claude Max for coding work, you've probably noticed:  
complex projects eat through your quota quickly — because Claude reads entire files to answer a single question.

**AI Context Engine reduces context token usage by ~80% per session.**

Here's why that matters:

| Session (10 tasks, ~10k LOC project) | Without | With AI Context |
|---|---|---|
| Session startup context | ~9,000 tokens | ~2,000 tokens |
| Per bug fix (avg. 3 files read) | ~5,400 tokens | ~900 tokens |
| Full session total | **~63,000 tokens** | **~11,000 tokens** |

Instead of reading `auth.ts` (2,500 tokens) to find one function,  
the engine serves the exact function signature + line number in ~80 tokens.

**The practical effect:**  
Claude Pro users often upgrade to Max because large codebases burn through rate limits.  
With AI Context Engine, a Claude Pro plan handles the same workload —  
because each interaction loads 5× less context.  
**Your Pro plan becomes as effective as Max for most coding sessions.**

---

Your codebase is not a collection of files.  
It is a system of constraints, rules, and dependencies.  
**AI Context Engine makes that system visible — before you commit.**

```
$ git commit -m "fix: update JWT validation"

  AI Context Engine
  ─────────────────────────────────────────────
  ⚠  INVARIANT [auth_first]  (hard)
     Auth-Check must precede all protected routes
     scope: src/app/api/**
     enforcement: middleware/auth.ts · api/users.ts

  ⚠  Gap detected: src/lib/auth.ts
     Typically changed together: middleware/auth.ts · login.tsx
     (co-changed 4× in past — 2 missing from this commit)

  ℹ  Intent: "fix JWT validation"
     Concepts affected: authentication · session · security
  ─────────────────────────────────────────────
```

---

## Why this exists

Modern AI coding tools fail at one thing:  
They read code. They don't understand systems.

| | Without AI Context | With AI Context |
|---|---|---|
| Agent reads | entire files | structured graph |
| Token usage | high | low |
| Knows what breaks | no | yes, before commit |
| Understands invariants | no | yes |
| Learns from past bugs | no | yes (cross-session) |

---

## Architecture

Five layers. Each one built on the previous.

```
┌──────────────────────────────────────┐
│            INTENT LAYER              │  ← WHY code changes
│  Commit intent · Feature purpose     │
├──────────────────────────────────────┤
│           INVARIANT LAYER            │  ← WHAT must never break
│  System rules · Security contracts   │
├──────────────────────────────────────┤
│            CHANGE GRAPH              │  ← HOW things affect each other
│  Impact graph · Co-change patterns   │
├──────────────────────────────────────┤
│            SYMBOL GRAPH              │  ← WHERE things are
│  Functions · Signatures · used_in    │
├──────────────────────────────────────┤
│             CODE BASE                │  ← WHAT exists
│  Files · Interfaces · Types          │
└──────────────────────────────────────┘
```

---

## Key Capabilities

### 1. Invariant Engine
Define rules that must never break. The engine checks every commit.

```yaml
# _ai_context/invariants.yaml
invariants:
  - id: auth_first
    level: hard
    rule: "Auth must be validated before protected routes"
    scope: "src/app/api/**"
    depends: ["src/lib/auth.ts", "src/middleware.ts"]
```

When `auth.ts` is changed → instant warning with enforcement points.

### 2. Symbol Map with Signatures and Callers

```
validateJWT            L342   (token: string): User | null
  → used in: middleware/auth.ts · api/users.ts · api/admin.ts

saveFact               L43    (root, type, content, priority): SaveResult
  → used in: capture_from_diff.ts · memory_save.ts
```

Navigate any codebase in seconds. No full file reads.

### 3. Impact Graph — Learned from Git History

```yaml
edges:
  - source: src/lib/auth.ts
    affects: [Login.tsx, Signup.tsx, middleware/auth.ts]
    confidence: 4        # learned from 4 real co-changes
```

When files change together repeatedly, the graph learns and warns.

### 4. Gap Detection

```
⚠ Incomplete change?  src/lib/auth.ts
  Usually also changed: middleware/auth.ts · login.tsx
  (4× co-changed in history — 2 missing from this commit)
```

### 5. MCP Server for Claude Code / Cursor

```
memory_search("auth bug")     → finds relevant gotchas cross-project
session_context()             → compact context instead of 4+ files  
capture_from_diff()           → learns from every commit automatically
locate("login button broken") → single lookup across ALL of the above (v7)
```

### 6. `locate()` — one lookup instead of six files (v7)

The single entry point that fans out over Interaction Map, Symbol Map,
Interfaces, Gotchas/Debug-Patterns, Invariants and the Impact Graph —
so the agent doesn't need to know which of the six index files to check.

```
locate("login button reagiert nicht")
→
🔘 button `LoginButton`  src/components/LoginForm.tsx:47
   handler: handleLogin  |  state: -  |  endpoint: POST /api/auth/login

⚡ Verwandte Gotchas/Patterns:
   auth_version [P2] — ⚠ PRÜFEN (Code neuer als seen 2026-04-14)

🔒 Invariante:
   auth_first (hard) — Auth-Check muss vor jeder state-ändernden Route stehen

🕸 Impact: src/lib/auth.ts ändert sich oft mit middleware.ts, login.tsx
```

Available both as the `locate` MCP tool and as a CLI
(`bash _ai_context/scripts/ai-symptom-router.sh "<description>"`, which
delegates to `locate()` under the hood and falls back to its own
keyword router if the MCP build isn't available).

### 7. `drawers.yaml` — content-based routing manifest (v7)

Instead of four fixed domains, a declarative manifest maps glob patterns
and keywords to an index file per "drawer" (`ui_controls`, `api`, `auth`,
`data`, `state`, `infra` by default — extend with your own, e.g.
`payments`). `setup_ai_context.sh` generates one from the detected stack;
`locate()` uses it to route a query to the right index first.

### 8. Freshness model — is this gotcha still true? (v7)

Every registry chunk gets `seen` (when it was last confirmed) and
`code_touched` (the newest git-log date across its `@`-referenced files,
computed automatically). The derived `status` — `fresh` / `check`
(code changed after `seen`) / `orphan` (the file is gone) — shows up
directly in `locate()`'s answer card and in `ai-context-doctor.sh`'s
`freshness` check, so the agent can tell a still-valid gotcha from one
that predates a later refactor.

---

## Installation

**Step 1 — Clone and run setup in your project:**

```bash
git clone https://github.com/studiodkmn-ctrl/ai-context-engine
cd your-project
bash /path/to/ai-context-engine/setup_ai_context.sh
```

This creates `_ai_context/` in your project with:
- Symbol map, interface snapshot, impact graph
- Invariant definitions bootstrapped from your security patterns
- Session context generator
- Post-commit hook for automatic learning

**Step 2 — Add MCP server (Claude Code / Cursor):**

```jsonc
// .mcp.json in your project
{
  "mcpServers": {
    "ai-context": {
      "command": "node",
      "args": ["PATH_TO/ai-context-engine/mcp/dist/server.js"]
    }
  }
}
```

**Step 3 — Generate your first session context:**

```bash
bash _ai_context/scripts/ai-session-prep.sh
```

**Global install (recommended):** `bash install.sh` installs everything to
`~/.ai-context`, adds shell aliases (`ai-context-setup`, `ai-doctor`, …) and
a self-update loop — once installed, the engine checks its source at most
once per week, backs itself up and updates itself and all registered
projects automatically (visible in the session log, rollback via
`ai-context-rollback.sh`, integrity-guarded against source tampering).

**Uninstall:** `bash uninstall.sh` — lists exactly what will be removed
(global store, shell block, hooks), asks once, never touches your projects'
`_ai_context/` knowledge or foreign git hooks.

---

## Supported platforms

| Platform | Status |
|---|---|
| macOS | ✅ tested (primary development platform) |
| Linux | ✅ tested (CI runs on Ubuntu) |
| WSL | ⚠️ untested — should work (bash + python3 + node), no guarantees |
| Windows (native) | ❌ not supported — the engine is bash-based |

---

## Commands

```bash
# Check invariants against staged changes
bash _ai_context/scripts/ai-invariant-check.sh --staged

# Route a bug description to likely source files  
bash _ai_context/scripts/ai-symptom-router.sh "login button not responding"

# Regenerate symbol map with signatures and callers
bash _ai_context/scripts/ai-symbol-map.sh

# Detect context drift (stale files, script updates)
bash _ai_context/scripts/ai-context-doctor.sh
```

---

## MCP Tools (in Claude Code)

```
locate("login button broken")    # single lookup — try this first
capture_from_diff(apply=true)    # auto-learn from current commit
memory_search("jwt expiry")      # search across all your projects  
session_context()                # load compact project context
```

---

## Invariant Levels

| Level | Meaning | In Commit Hook |
|---|---|---|
| `hard` | System breaks if violated | Blocks + error |
| `soft` | Degraded behavior, warning | Warning shown |
| `hint` | Code smell, best practice | Info shown |

---

## What it looks like inside Claude Code

When AI Context Engine is active, Claude knows:

- Which invariants your change might violate
- Which files are typically changed together  
- What functions call what — without reading entire files
- What past bugs looked like in this area of code

Instead of:
```
"Let me read auth.ts... and middleware.ts... and login.tsx..."
```

Claude says:
```
"The auth_first invariant is affected. 
 Enforcement points: middleware/auth.ts:67 and api/users.ts:23.
 Past fix: commit a4f2b1 added session check here."
```

---

## Roadmap

- [x] Impact Graph — learned co-change relationships
- [x] Symbol Map — functions, signatures, callers (`used_in`)
- [x] Invariant Layer — hard/soft/hint rules with file deps
- [x] Gap Detection — missing co-changes flagged at commit
- [x] Intent Tagging — commit meaning extracted + stored
- [x] MCP Server — Claude Code / Cursor integration
- [x] Cross-project memory — learnings transfer between projects
- [x] `locate()` — single-lookup routing across all indices (v7)
- [x] `drawers.yaml` — declarative content-based routing manifest (v7)
- [x] Freshness model — `seen`/`code_touched`/`status` per chunk, derived from git history (v7)
- [ ] Invariant discovery — auto-suggest invariants from bug history
- [ ] Static verification — verify invariants are enforced in code
- [ ] System Behavior Model — goal-state layer above invariants

---

## Philosophy

> *Your codebase is not files. It's a system of constraints.*  
> *Code is implementation. Rules are truth.*

AI Context Engine is the layer that makes rules explicit —  
so AI agents can reason about your system, not just read it.

---

## Contributing

This is an open system. Add your own invariants, extend the impact graph, build integrations.

```bash
# Add a new invariant
vi _ai_context/invariants.yaml

# Teach the impact graph a new relationship
bash _ai_context/scripts/ai-impact-learn.sh src/auth.ts src/middleware.ts
```

---

**Star this repo if you believe coding agents should understand systems, not just files.**
