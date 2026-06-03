# AI Context System v6.3

Zero-touch context management for Claude Code — with built-in **local PII anonymization**, automatic stack detection, and semantic chunk search.

---

## Why AI Context?

Every time you start a Claude session, you have to re-explain your project. AI Context solves this automatically: it reads your codebase, builds a compressed session context, and loads it before Claude sees a single word you type.

At the same time, **your sensitive business data never leaves your machine in raw form**. Names, amounts, IBANs, company names — all replaced locally before reaching Claude.

---

## What's new in v6.3

| Feature | v5.x | v6.3 |
|---|---|---|
| Installation | Single mode | **Simple** (default) + **Pro** (Ollama + RAG) |
| IDE Integration | Terminal only | **Universal** (Terminal, VS Code, Cursor, JetBrains via SessionStart hook) |
| Chunk Search | — | **Registry + semantic HTML anchors** |
| RAG Cache | — | **Ollama Embeddings (nomic-embed-text)** |
| Privacy Layer | — | **`ai-anon` — local anonymization before Claude** |
| PII Guardrail | — | **UserPromptSubmit hook — raw PII is blocked before transmission** |
| Multi-Session Stats | — | **Weekly/monthly token usage (`ai-stats`)** |
| Behavior Rules | — | **`_SESSION.md` rules enforce Gotcha-Detection, Auto-Apply** |
| Django/Python ORM | Basic | **Enhanced: models.py scan** |
| macOS Compatibility | Partial | **Full (BSD tools)** |

---

## Installation

### Simple (default — no Ollama required)

```bash
git clone https://github.com/studiodkmn-ctrl/ai-context-v5.2.git
cd ai-context-v5.2
bash install.sh
# Close and reopen your terminal
```

Includes: templates, registry, shell aliases, zero-touch `claude` wrapper, PII anonymization, block-mode safety hook.

### Pro (+ Ollama + RAG Cache + Embeddings)

```bash
bash install.sh --pro
```

Includes everything in Simple, plus:
- Ollama installation + `nomic-embed-text` model (~274 MB)
- launchd/systemd auto-start
- Semantic chunk search via embeddings
- `ai-rag` and `ai-registry` commands

> `--skip-ollama` is deprecated and will be ignored with a notice.

---

## Privacy Protection — Two Layers

This is the core feature. **Your company data stays on your machine.**

### Layer A — Explicit Anonymization (`ap:`)

Type `ap:` before any text containing real names, companies, amounts, or personal data. The system replaces everything locally, copies the anonymized version to your clipboard, and you paste it into Claude.

```bash
ap: Müller GmbH owes us $1,250 since 15.03.2026, invoice R-2024-088
# Clipboard receives:
#   [FIRMA_1] owes us $1,250 since [DAT_1], invoice R-2024-088
```

**Invoice mode (automatic):** When the text contains calculation keywords (*owes, costs, total, invoice, sum, VAT*), amounts are preserved so Claude can calculate. Only names, companies, and contact data are replaced.

```bash
ap: Peter Schmidt owes Müller GmbH $1,250 for invoice R-2024-088
# → [P1] owes [FIRMA_1] $1,250 for invoice R-2024-088
#   (amount stays — Claude can calculate; names are gone)
```

Then paste into Claude, get a full response using placeholders, copy the response, and run:

```bash
ar
# Clipboard now has the original names restored — session map deleted
```

### Layer B — Automatic Block (Option C)

If you forget `ap:` and type raw PII directly into Claude — an email, IBAN, phone number, a company name like "Müller GmbH", or an amount like "$50,000" — the **UserPromptSubmit hook** blocks the prompt completely before it reaches Claude:

```
🛑 Prompt blocked — sensitive data detected (Company, Amount).
   Claude never saw your prompt.
   → Re-enter with prefix: ap: <your text>
```

Claude never sees the raw data. The hook runs in **all Claude environments** (Terminal, VS Code, Cursor, JetBrains). If placeholders are already present in the prompt (`[P1]`, `[B1]` …), the hook passes through silently — Layer A already fired.

### Placeholder Schema

| Category | Placeholder | Example |
|---|---|---|
| Person | `[P1]`, `[P2]` | "Dr. Weber", "Max Mustermann" |
| Location | `[ORT_1]` | "80331 Munich", "Main Street 5" |
| Phone | `[TEL_1]` | "+49 30 1234567" |
| E-Mail | `[MAIL_1]` | "weber@company.com" |
| Amount | `[B1]` | "$50,000" *(preserved in invoice mode)* |
| Date | `[DAT_1]` | "15.03.2026" |
| Time | `[UHR_1]` | "14:30" |
| IBAN | `[IBAN_1]` | "DE89 3704 0044 …" |
| Company | `[FIRMA_1]` | "Müller GmbH" |
| Project | `[PROJ_1]` | "Project Website Redesign" |

Session maps are stored per day under `~/.ai-context/maps/session_YYYY-MM-DD.json`. After `ar`, the session file is **deleted** — sensitive mappings are never stored permanently.

**Additional commands:**

```bash
ai-anon --show                  # display current mapping table
ai-anon --clear                 # delete all session maps
ai-anon --detect "text"         # exit 0=placeholders, 1=raw PII, 2=clean
```

---

## Daily Usage

### Zero-Click (works everywhere)

```bash
cd my-project
claude                          # _SESSION.md is generated automatically
```

v6.3 uses **two mechanisms** for universal integration:

1. **SessionStart hook** in `.claude/settings.json` (project-local) and `~/.claude/settings.json` (global) — works in **all** Claude environments: Terminal, VS Code Claude Extension, Cursor, JetBrains.
2. **Shell wrapper** `claude()` in `.zshrc`/`.bashrc` as a terminal fallback.

Whether you type `claude` in the terminal or open the VS Code extension — context is ready before you type a word.

### VS Code / Cursor / JetBrains

After `ai-context-setup`, `.claude/settings.json` is in your project. Open the project in VS Code and the Claude extension triggers the SessionStart hook automatically:

```
🧠 AI Context: Preparing context...
✅ Session ready (~310 tokens) — Domain: backend
```

### New Project Setup

```bash
ai-context-setup my-project
```

Creates `_ai_context/` with auto-detected stack (Next.js, Django, FastAPI, Go …).

### Manual Commands

```bash
ai-prep                         # generate _SESSION.md manually
ai-prep --task "Auth refactor"  # task-specific (uses RAG in Pro mode)
ai-prep --full                  # all files inline

ai-context-sync --export        # _SESSION.md → clipboard (for Claude.ai chat)
ai-context-sync --list          # list all projects
ai-context-sync --restore       # restore context from ~/.ai-context/

ai-stats                        # token stats (last 7 days)
ai-stats --month                # last 30 days
ai-stats --all                  # all time
```

---

## Pro-only Features

> Pro mode requires Ollama (`bash install.sh --pro`). Free to run locally — no cloud, no API costs.

### Semantic Chunk Search

```bash
ai-registry --add-anchors       # set HTML anchors in context files
ai-registry --scan              # build registry (registry.yaml)
ai-registry --find 'auth'       # semantic keyword search
```

### RAG Cache (Ollama Embeddings)

```bash
ai-rag --stats                  # RAG cache statistics
ai-rag --embed-chunks           # embed all chunks via Ollama
ai-rag --find "JWT validation"  # semantic similarity search
```

When you run `ai-prep --task "Auth refactor"`, Pro mode automatically finds the most relevant chunks via embeddings and injects them into `_SESSION.md`. Cache is invalidated after every `git commit` via a post-commit hook.

---

## Architecture

```
~/.ai-context/                  ← Global store (installed)
├── _ai_context_template/       ← Base templates for new projects
├── hooks/
│   └── pii-warn.sh             ← UserPromptSubmit block hook (global)
├── ai-anon.sh                  ← Local anonymizer
├── projects/                   ← Context mirror per project
│   └── my-project/
├── shared/
│   ├── gotchas_global.md       ← Cross-project gotchas
│   └── patterns_global.md      ← Debug patterns
├── setup_ai_context.sh         ← Project setup script
└── CLAUDE.md                   ← Global Claude instructions

my-project/_ai_context/         ← Per-project (auto-generated)
├── _SESSION.md                 ← AUTO-GENERATED — Claude reads this first
├── _ai_index.md                ← Micro index (~150 tokens)
├── _quick_facts.md             ← Permanent facts (stack, env, ports)
├── registry.yaml               ← Chunk registry with HTML anchors [Pro]
├── .rag_cache/                 ← Embedding cache [Pro]
├── _idx/                       ← Domain indices (~80 tokens each)
│   ├── frontend.md
│   ├── backend.md
│   ├── infra.md
│   └── project.md
├── _gotchas.md                 ← Technical traps (max 15)
├── _temp_notes.md              ← Sprint/tasks (Recent Changes max 5)
├── frontend/
├── backend/
├── architecture.md
├── decisions.md
├── debug_patterns.md
├── security.md
└── testing.md
```

### Context Routing (3 tiers)

```
_ai_index.md (~150 tok) → _idx/domain.md (~80 tok) → file.md (~200 tok)
Max 3 files per chain. Max 4 files per session.
```

---

## Supported Stacks (20+)

| Category | Frameworks |
|---|---|
| JavaScript/TypeScript | Next.js, Nuxt, React, Vue, Svelte, Angular, Astro, Remix, Express, Fastify, NestJS, Hono |
| Python | Django, FastAPI, Flask, LangChain, Claude API |
| Rust | Actix, Axum |
| Go | Standard + Gin, Echo |
| Other | Ruby/Rails, Java/Spring, PHP/Laravel, Flutter/Dart |
| Infra | Docker, Terraform |

Django projects are detected via `manage.py` + `models.py` scan. Frontend directories are not created for pure backend projects.

---

## Upgrading from v5.x

```bash
# 1. Get the new release
cd ai-context-v5.2
bash install.sh          # overwrites ~/.ai-context/_ai_context_template/

# 2. Update an existing project
cd my-project
ai-context-setup my-project   # regenerates _ai_context/ with new templates

# 3. Optional: build registry (Pro)
ai-registry --add-anchors && ai-registry --scan
ai-rag --embed-chunks
```

Existing `_gotchas.md`, `decisions.md`, etc. are preserved — only templates are updated.

---

## Uninstall

```bash
# Remove shell aliases
# From ~/.zshrc / ~/.bashrc: delete everything between "# AI Context v6.3" blocks

# Remove global store
rm -rf ~/.ai-context

# Optional: uninstall Ollama (Pro)
brew uninstall --cask ollama    # macOS
```

---

## Context Format

Gotchas, rules, and patterns use structured code format:

```
ID: UNIQUE_ID
→ Description
✗ WRONG:   <bad example>
✓ CORRECT: <good example>
? Symptom:  <how to recognize it>
@ Files:    <affected files>
P: 1        (1=critical, 2=important, 3=nice-to-know)
```

`⇒` is a pointer — references other files, never copied inline. Claude loads referenced files on demand only.

---

## License

MIT — free for personal and commercial use.
