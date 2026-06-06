# AI Context Engine

**A pre-commit reasoning layer for AI coding agents.**

> *"We don't make AI smarter. We give AI a memory of your system."*

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
```

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
