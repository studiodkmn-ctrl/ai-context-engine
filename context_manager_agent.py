"""
ContextManagerAgent v3 — Agent #10 for the Idea-to-Folder System (AI Context v4)

Improvements over v2:
  - Multi-Fingerprint: pkg.json hash + schema hash + .env flag in _ai_index.md
  - JSON sidecar: each .md gets a companion .json for fast resync() without Markdown parsing
  - _find_stale_files(): JSON sidecar fast path, falls back to _ai_index.md (v3 compat)
  - decisions.md: now invalidated by package.json changes (new architecture decisions)
  - _write_files(): writes .json sidecar alongside every .md automatically
  - quality_check(): validates files aren't too long or contain placeholders

Integration:
  from context_manager_agent import ContextManagerAgent, integrate_into_orchestrator

  # Full generation (end of Idea-to-Folder run):
  agent = ContextManagerAgent(project_output_dir="./output/my-project")
  agent.run(project_metadata=metadata)

  # Resync stale files only (e.g. end of sprint):
  agent.resync(project_output_dir="./output/my-project")
"""

import os
import json
import subprocess
from datetime import date
from pathlib import Path
from dataclasses import dataclass, field
from typing import Optional
import anthropic

# =============================================================================
# Data Structures
# =============================================================================

@dataclass
class ProjectMetadata:
    """
    Filled by the Idea-to-Folder orchestrator and passed to this agent.
    Adapt fields to match your existing metadata object.
    """
    project_name: str
    project_description: str
    stack: dict                          # e.g. {"frontend": "Next.js 14", "orm": "Prisma"}
    folder_structure: str                # Textual representation of generated structure
    generated_files: list[str]           # All generated file paths
    architecture_decisions: list[str] = field(default_factory=list)
    api_routes: list[dict] = field(default_factory=list)
    db_models: list[dict] = field(default_factory=list)
    components: list[dict] = field(default_factory=list)
    sprint_goal: str = "Initial project setup complete"
    known_gotchas: list[str] = field(default_factory=list)


@dataclass
class ContextManagerConfig:
    model: str = "claude-haiku-4-5-20251001"   # Haiku: no complex reasoning needed
    max_tokens: int = 2048
    context_dir_name: str = "_ai_context"
    today: str = field(default_factory=lambda: date.today().strftime("%Y-%m-%d"))
    max_file_lines: int = 80                   # Quality gate: warn if file exceeds this


# =============================================================================
# Agent
# =============================================================================

class ContextManagerAgent:
    """
    Agent #10: Creates and maintains _ai_context/ with all context files.

    Generation strategy:
    - _quick_facts.md, _ai_index.md, current_sprint.md → direct from metadata (0 LLM tokens)
    - architecture.md, api.md, database.md, components.md, state.md, decisions.md
      → Claude Haiku with dense, structured prompts
    """

    # All files this agent manages
    ALL_FILES = [
        "_quick_facts.md",
        "_ai_index.md",
        "architecture.md",
        "decisions.md",
        "current_sprint.md",
        "frontend/components.md",
        "frontend/state.md",
        "backend/api.md",
        "backend/database.md",
    ]

    def __init__(self, project_output_dir: str, config: Optional[ContextManagerConfig] = None):
        self.output_dir = Path(project_output_dir)
        self.config = config or ContextManagerConfig()
        self.context_dir = self.output_dir / self.config.context_dir_name
        self.client = anthropic.Anthropic()

    # =========================================================================
    # Public: Full generation
    # =========================================================================

    def run(self, project_metadata: ProjectMetadata) -> dict:
        """
        Main method — creates complete _ai_context/ folder.
        Returns dict with stats.
        """
        print(f"\n🚀 ContextManagerAgent v3 starting: {project_metadata.project_name}")
        self._create_directory_structure()

        generators = {
            "_quick_facts.md":       lambda: self._generate_quick_facts(project_metadata),
            "architecture.md":       lambda: self._generate_architecture(project_metadata),
            "decisions.md":          lambda: self._generate_decisions(project_metadata),
            "current_sprint.md":     lambda: self._generate_sprint(project_metadata),
            "frontend/components.md": lambda: self._generate_components(project_metadata),
            "frontend/state.md":     lambda: self._generate_state(project_metadata),
            "backend/api.md":        lambda: self._generate_api(project_metadata),
            "backend/database.md":   lambda: self._generate_database(project_metadata),
        }

        # Generate all files
        results = {}
        for path, generator in generators.items():
            print(f"  ⚙️  {path}...", end="", flush=True)
            content = generator()
            results[path] = content
            print(" ✅")

        # _ai_index.md is built AFTER all other files (needs TL;DRs)
        print(f"  ⚙️  _ai_index.md (with TL;DRs)...", end="", flush=True)
        results["_ai_index.md"] = self._generate_index(project_metadata, results)
        print(" ✅")

        # Write all files
        written = self._write_files(results)

        # Quality check
        issues = self._quality_check()
        if issues:
            print(f"\n  ⚠️  Quality issues found:")
            for issue in issues:
                print(f"     {issue}")

        print(f"\n✅ ContextManagerAgent v3 done — {written}/9 files written")
        print(f"   Path: {self.context_dir}\n")
        return {"files_written": written, "context_dir": str(self.context_dir), "issues": issues}

    # =========================================================================
    # Public: Resync stale files only
    # =========================================================================

    def resync(self, project_output_dir: Optional[str] = None) -> dict:
        """
        Resync mode: regenerates ONLY files marked as ❌ or ⚠️ in _ai_index.md.
        Use at sprint end or when context has drifted.

        This does NOT require project_metadata — it reads stale markers from
        the existing _ai_index.md and regenerates only those files.
        """
        if project_output_dir:
            self.output_dir = Path(project_output_dir)
            self.context_dir = self.output_dir / self.config.context_dir_name

        if not self.context_dir.exists():
            print(f"❌ No _ai_context/ found at {self.context_dir}")
            return {"files_resynced": 0}

        stale_files = self._find_stale_files()
        if not stale_files:
            print("✅ All context files are fresh (✅). Nothing to resync.")
            return {"files_resynced": 0}

        print(f"\n🔄 Resync: {len(stale_files)} stale files detected:")
        for f, marker in stale_files:
            print(f"   {marker} {f}")

        # For resync, we read existing content and ask Haiku to update it
        resynced = 0
        for relative_path, marker in stale_files:
            full_path = self.context_dir / relative_path
            if not full_path.exists():
                continue

            existing_content = full_path.read_text(encoding="utf-8")
            print(f"  🔄 Resyncing {relative_path}...", end="", flush=True)

            updated = self._resync_file(relative_path, existing_content)
            if updated:
                full_path.write_text(updated, encoding="utf-8")
                resynced += 1
                print(" ✅")
            else:
                print(" ⚠️  skipped (no content returned)")

        print(f"\n✅ Resync complete — {resynced}/{len(stale_files)} files updated")
        return {"files_resynced": resynced}

    # =========================================================================
    # Private: Directory structure
    # =========================================================================

    def _create_directory_structure(self):
        (self.context_dir / "frontend").mkdir(parents=True, exist_ok=True)
        (self.context_dir / "backend").mkdir(parents=True, exist_ok=True)

    def _write_files(self, results: dict) -> int:
        """Write all context files + JSON sidecar for each (v4: machine-readable companion)."""
        written = 0
        for relative_path, file_content in results.items():
            if file_content:
                file_path = self.context_dir / relative_path
                file_path.parent.mkdir(parents=True, exist_ok=True)
                file_path.write_text(file_content, encoding="utf-8")

                # JSON sidecar — enables resync() to check status without parsing Markdown
                json_path = file_path.with_suffix('.json')
                import re as _re
                status_match = _re.search(r'Status:\*\* ([✅⚠️❌])', file_content)
                sidecar = {
                    "file": relative_path,
                    "status": status_match.group(1) if status_match else "✅",
                    "last_updated": self.config.today,
                    "lines": len(file_content.splitlines()),
                }
                json_path.write_text(json.dumps(sidecar, indent=2, ensure_ascii=False), encoding="utf-8")
                written += 1
        return written

    # =========================================================================
    # Private: Quality check
    # =========================================================================

    def _quality_check(self) -> list[str]:
        """Validates generated files aren't too long or placeholder-heavy."""
        issues = []
        for relative_path in self.ALL_FILES:
            full_path = self.context_dir / relative_path
            if not full_path.exists():
                continue
            content = full_path.read_text(encoding="utf-8")
            lines = content.splitlines()

            if len(lines) > self.config.max_file_lines:
                issues.append(f"⚠️  {relative_path}: {len(lines)} lines (max {self.config.max_file_lines})")

            placeholder_count = content.count("[DATE]") + content.count("[HIER EINTRAGEN]")
            if placeholder_count > 3:
                issues.append(f"⚠️  {relative_path}: {placeholder_count} unfilled placeholders")

        return issues

    # =========================================================================
    # Private: Stale file detection
    # =========================================================================

    def _find_stale_files(self) -> list[tuple[str, str]]:
        """Returns list of (relative_path, marker) for stale files.
        v4: Prefers JSON sidecars (fast, no Markdown parsing) — falls back to _ai_index.md.
        """
        stale = []

        # Fast path: check JSON sidecars
        json_files_found = False
        for relative_path in self.ALL_FILES:
            if relative_path in ["_ai_index.md", "_quick_facts.md"]:
                continue
            json_path = (self.context_dir / relative_path).with_suffix(".json")
            if json_path.exists():
                json_files_found = True
                try:
                    data = json.loads(json_path.read_text(encoding="utf-8"))
                    marker = data.get("status", "✅")
                    if marker in ["❌", "⚠️"]:
                        stale.append((relative_path, marker))
                except Exception:
                    pass

        if json_files_found:
            return stale

        # Fallback: parse _ai_index.md (v3 compatibility)
        index_path = self.context_dir / "_ai_index.md"
        if not index_path.exists():
            return []
        index_content = index_path.read_text(encoding="utf-8")
        for line in index_content.splitlines():
            if "❌" in line and "`" in line:
                parts = line.split("`")
                if len(parts) >= 2:
                    stale.append((parts[1], "❌"))
            elif "⚠️" in line and "`" in line:
                parts = line.split("`")
                if len(parts) >= 2:
                    stale.append((parts[1], "⚠️"))
        stale = [(f, m) for f, m in stale if f not in ["_ai_index.md", "_quick_facts.md"]]
        return stale

    # =========================================================================
    # Private: Git fingerprint
    # =========================================================================

    def _get_git_hash(self) -> str:
        """Gets current git hash from the project directory."""
        try:
            result = subprocess.run(
                ["git", "log", "-1", "--format=%H"],
                cwd=self.output_dir,
                capture_output=True, text=True, timeout=5
            )
            return result.stdout.strip() or "no-git"
        except Exception:
            return "no-git"

    def _sanitize(self, text: str, max_len: int = 500) -> str:
        """
        Sanitize user-supplied strings before injecting into LLM prompts.
        Prevents prompt injection and JSON formatting issues.
        """
        if not text:
            return ""
        # Remove characters that could confuse prompt structure
        sanitized = text.replace("```", "'''")
        sanitized = sanitized.replace("---", "- - -")
        sanitized = sanitized.replace("TASK", "Task")
        sanitized = sanitized.replace("CONTEXT", "Context")
        sanitized = sanitized.replace("CONSTRAINTS", "Constraints")
        sanitized = sanitized.replace("OUTPUT FORMAT", "Output Format")
        # Truncate to avoid token explosion from untrusted inputs
        return sanitized[:max_len] if len(sanitized) > max_len else sanitized

    def _sanitize_stack(self, stack: dict) -> dict:
        """Sanitize all stack values before use in prompts."""
        return {
            self._sanitize(k, 50): self._sanitize(v, 100)
            for k, v in stack.items()
            if k and v
        }

    # =========================================================================
    # Private: LLM helper
    # =========================================================================

    def _call_haiku(self, system_prompt: str, user_prompt: str) -> str:
        try:
            response = self.client.messages.create(
                model=self.config.model,
                max_tokens=self.config.max_tokens,
                system=system_prompt,
                messages=[{"role": "user", "content": user_prompt}]
            )
            return response.content[0].text
        except Exception as e:
            print(f"\n  ⚠️  Haiku call failed: {e}")
            return ""

    def _resync_file(self, relative_path: str, existing_content: str) -> str:
        """Asks Haiku to update a stale file based on its current content."""
        system = """You are a technical documentation assistant maintaining AI context files.
The file provided is marked as stale (❌ or ⚠️).
Update it to reflect current best practices and remove obviously outdated placeholders.
Keep the same structure. Be concise — max 80 lines.
Return ONLY the updated markdown content, no preamble."""

        user = f"""Update this stale context file.
File: {relative_path}
Today's date: {self.config.today}

Current content:
{existing_content}

Instructions:
1. Replace [DATE] placeholders with {self.config.today}
2. Change Status from ❌/⚠️ to ✅
3. Keep all structural elements intact
4. Do NOT invent new technical details — keep existing content"""

        return self._call_haiku(system, user)

    # =========================================================================
    # Private: Direct generation (no LLM)
    # =========================================================================

    def _generate_quick_facts(self, meta: ProjectMetadata) -> str:
        """_quick_facts.md — direct from metadata, 0 LLM tokens."""
        today = self.config.today
        stack_str = " + ".join([f"{v}" for v in meta.stack.values() if v])
        gotchas = "\n".join([f"{i+1}. {g}" for i, g in enumerate(meta.known_gotchas[:5])]) \
                  if meta.known_gotchas else "1. [Add project-specific gotchas here]"

        return f"""# ⚡ Quick Facts — {meta.project_name}
> **Always load this file. ~150 tokens. Claude: Read before any task.**
> Last updated: {today}

---

## Identity
```
Project:  {meta.project_name}
Stack:    {stack_str}
Phase:    MVP
```

---

## 🚨 Critical Gotchas (read before writing any code)
```
{gotchas}
```

---

## 📍 Key File Paths
```
DB schema:       prisma/schema.prisma
Auth config:     src/lib/auth.ts
Prisma client:   src/lib/prisma.ts  ← NEVER new PrismaClient() directly
Global state:    src/store/
API routes:      src/app/api/
Components:      src/components/
```

---

## 🎯 Sprint Snapshot
```
Sprint goal:   {meta.sprint_goal}
Active task:   Initial setup — review generated files
Blocked by:    Nothing
Last change:   {today} — Project generated via Idea-to-Folder
```

---

## 🔑 Environment Variables (required to run)
```
DATABASE_URL        ← Prisma connection string
NEXTAUTH_SECRET     ← Min 32 chars
NEXTAUTH_URL        ← e.g. http://localhost:3000
```

---
> To update: edit this file + set ✅ in _ai_index.md staleness table
"""

    def _generate_sprint(self, meta: ProjectMetadata) -> str:
        """current_sprint.md — direct from metadata."""
        today = self.config.today
        completed = "\n".join([f"- [x] `{f}` generated" for f in meta.generated_files[:10]])
        if len(meta.generated_files) > 10:
            completed += f"\n- [x] ... and {len(meta.generated_files) - 10} more files"

        return f"""# 🏃 Current Sprint
**Status:** ✅ Fresh · **Updated:** {today} · **Period:** {today} → [END]

---

## 🎯 Sprint Goal
```
{meta.sprint_goal}
```

---

## 📋 Tasks

### 🔨 In Progress
- [ ] Review context files and complete placeholders
- [ ] Finalize stack configuration

### 📋 Open
- [ ] Implement first real features
- [ ] Set up tests
- [ ] Configure CI/CD

### ✅ Done (generated by Idea-to-Folder)
{completed}

---

## 🧠 Important Context for Claude
```
Currently building:   First feature after project generation
Status:               Project skeleton generated, configuration pending
Next step:            Check package.json, set env vars, set up DB
```

---

## 📝 Daily Log

### {today} — Project generated via Idea-to-Folder
- Complete project structure created automatically
- _ai_context/ auto-populated (ContextManagerAgent v3)
- Next step: review project + fill in missing configuration

```
[{today} 00:00] | Task: Projekt via Idea-to-Folder generiert
  Gemacht:      Komplette Projektstruktur + _ai_context/ erstellt
  Source-Files: (generiert)
  Context-Files: alle 9 Dateien ✅
  Problem:      -
  Nächster:     package.json prüfen, env-Variablen setzen, DB aufsetzen
```
- Next step: review project + fill in missing configuration
"""

    def _generate_index(self, meta: ProjectMetadata, generated_contents: dict) -> str:
        """
        _ai_index.md — built AFTER other files so we can extract TL;DRs.
        Calls Haiku once to generate TL;DRs for all 7 content files.
        """
        today = self.config.today
        git_hash = self._get_git_hash()
        stack_str = " + ".join([f"{k}: {v}" for k, v in meta.stack.items()])

        # Collect summaries of generated files for Haiku to distill
        file_summaries = {}
        for fname in ["architecture.md", "frontend/components.md", "frontend/state.md",
                       "backend/api.md", "backend/database.md", "decisions.md", "current_sprint.md"]:
            content = generated_contents.get(fname, "")
            if content:
                # Give Haiku only first 30 lines of each file
                preview = "\n".join(content.splitlines()[:30])
                file_summaries[fname] = preview

        # Ask Haiku for TL;DRs (one call for all files)
        tldrs = self._generate_tldrs(file_summaries)

        has_agents = any("agent" in f.lower() for f in meta.generated_files)
        agent_row = "| AI agents, pipelines, models | `agents.md` |\n" if has_agents else ""
        gotchas = "\n".join([f"- {g}" for g in meta.known_gotchas]) if meta.known_gotchas \
                  else "- [Add project-specific gotchas here]"

        return f"""# 🧠 AI Context Index v3
> **Claude: Load `_quick_facts.md` first, then this file. Together ~450 tokens.**
> **Read TL;DR column — you may not need to load any additional file.**

---

## 📌 Project Overview
```
Project:      {meta.project_name}
Stack:        {stack_str}
Description:  {meta.project_description}
Generated:    {today}
```

---

## 🔑 Session Fingerprint
```
Last known git hash:    {git_hash}
pkg.json hash:          n/a
schema hash:            n/a
.env exists:            unknown
Last session date:      {today}
Files changed since:    (tracked by post-commit hook)
```

**Startup check:**
```bash
git log -1 --format="%H %s"
```
If hash matches → context is fresh. If differs → check Auto-Invalidation Rules below.

---

## 🗺️ Routing Table + TL;DRs

> **Claude: Read TL;DR column first. If it answers your question, don't load the full file.**

| File | Status | Updated | TL;DR |
|---|---|---|---|
| `_quick_facts.md` | ✅ | {today} | Always loaded. Gotchas + sprint snapshot. |
| `architecture.md` | ✅ | {today} | {tldrs.get('architecture.md', '[see file]')} |
| `frontend/components.md` | ✅ | {today} | {tldrs.get('frontend/components.md', '[see file]')} |
| `frontend/state.md` | ✅ | {today} | {tldrs.get('frontend/state.md', '[see file]')} |
| `backend/api.md` | ✅ | {today} | {tldrs.get('backend/api.md', '[see file]')} |
| `backend/database.md` | ✅ | {today} | {tldrs.get('backend/database.md', '[see file]')} |
| `decisions.md` | ✅ | {today} | {tldrs.get('decisions.md', '[see file]')} |
| `current_sprint.md` | ✅ | {today} | {tldrs.get('current_sprint.md', '[see file]')} |

**Staleness:** ✅ Fresh · ⚠️ Maybe stale · ❌ Stale (read source first)

---

## 📋 Full Routing Table

| Task Type | Load |
|---|---|
| UI, components, layouts, styling | `frontend/components.md` |
| State, stores, context, hooks | `frontend/state.md` |
| API routes, endpoints, auth | `backend/api.md` |
| DB schema, queries, migrations | `backend/database.md` |
{agent_row}| Stack overview, new feature planning | `architecture.md` |
| "Why was X built this way?" | `decisions.md` |
| Current sprint, open tasks | `current_sprint.md` |
| Full-stack feature (UI + API) | `frontend/components.md` + `backend/api.md` |
| DB migration + API change | `backend/database.md` + `backend/api.md` |
| New feature planning | `current_sprint.md` + `decisions.md` |
| Refactoring | `architecture.md` + `decisions.md` |

> ⚠️ **Maximum 2 files per task. Never all at once.**

---

## 🔄 Auto-Invalidation Rules

| Source file changed | Invalidates |
|---|---|
| `prisma/schema.prisma` | `backend/database.md` → ❌, `backend/api.md` → ⚠️ |
| `src/app/api/**` | `backend/api.md` → ❌ |
| `src/components/**` | `frontend/components.md` → ❌ |
| `store/**` / `context/**` / `lib/store*` | `frontend/state.md` → ❌ |
| `package.json` (new deps) | `architecture.md` → ⚠️ |
| `.env` / `.env.local` | `backend/api.md` → ⚠️ |
| `tailwind.config.*` | `frontend/components.md` → ⚠️ |
| `middleware.ts` | `backend/api.md` → ❌ |
| `src/lib/auth.ts` | `backend/api.md` → ❌, `frontend/state.md` → ⚠️ |

---

## ⚠️ Known Gotchas

```
{gotchas}
```

---

## 📝 Quick Change Log (last 5)
```
- {today}: Project generated via Idea-to-Folder
```

---
> Git hooks installed? → `ls .git/hooks/post-commit` to verify
"""

    def _generate_tldrs(self, file_summaries: dict) -> dict:
        """Single Haiku call to generate TL;DRs for all context files."""
        if not file_summaries:
            return {}

        files_text = "\n\n".join([
            f"=== {fname} ===\n{content}"
            for fname, content in file_summaries.items()
        ])

        system = """You generate ultra-compact TL;DR summaries for context files.
Each TL;DR must be ONE LINE, max 100 characters.
Focus on the most useful quick-reference fact for a developer.
Return ONLY a JSON object like: {"architecture.md": "...", "backend/api.md": "..."}
No markdown, no preamble, no explanation."""

        user = f"""Generate TL;DRs for these context files:

{files_text}

Rules:
- One line per file, max 100 chars
- Include key numbers (e.g. "8 endpoints", "3 models", "Zustand + React Query")
- Focus on what helps a developer decide whether to load the full file
- JSON output only"""

        result = self._call_haiku(system, user)
        try:
            clean = result.strip()
            if clean.startswith("```"):
                clean = clean.split("```")[1]
                if clean.startswith("json"):
                    clean = clean[4:]
            return json.loads(clean)
        except Exception:
            return {}

    # =========================================================================
    # Private: LLM-generated files
    # =========================================================================

    DENSE_SYSTEM = """You are a technical documentation assistant.
Write compact, dense Markdown for AI context files.
Rules:
- Write in German, but use English for all code, variable names, technical terms (API, Auth, Schema, Hook, Store, Route, etc.)
- Max {max_lines} lines total
- Use tables and code blocks, NOT prose paragraphs
- No verbose explanations — be as terse as a reference card
- Include Status header: **Status:** ✅ Aktuell · **Updated:** {today}
- Return ONLY markdown content, no preamble"""

    def _generate_architecture(self, meta: ProjectMetadata) -> str:
        system = self.DENSE_SYSTEM.format(max_lines=70, today=self.config.today)
        user = f"""Create architecture.md:

Project: {self._sanitize(meta.project_name)}
Description: {self._sanitize(meta.project_description, 300)}
Stack: {json.dumps(self._sanitize_stack(meta.stack), ensure_ascii=False)}
Generated files (sample): {json.dumps(meta.generated_files[:20], ensure_ascii=False)}
Folder structure:
{meta.folder_structure}

Must include:
1. Status header (✅, date: {self.config.today}, invalidated by: package.json, next.config.*)
2. Stack table (all detected technologies)
3. Project structure as ASCII tree
4. Module responsibilities table (5–6 rows)
5. Data flow (5 steps, one-liners)
6. Key architecture decisions (bullet list, 3 items, details → decisions.md)
7. Update log (one initial entry)"""
        return self._call_haiku(system, user)

    def _generate_decisions(self, meta: ProjectMetadata) -> str:
        system = self.DENSE_SYSTEM.format(max_lines=70, today=self.config.today)
        decisions_text = "\n".join(meta.architecture_decisions) if meta.architecture_decisions \
                         else "Infer from stack"
        user = f"""Create decisions.md with ADRs:

Project: {self._sanitize(meta.project_name)}
Stack: {json.dumps(self._sanitize_stack(meta.stack), ensure_ascii=False)}
Known decisions: {decisions_text}

Create 2–3 ADRs. Per ADR: ### ADR-NNN: Title, Date, Status, Context (1 sentence),
Decision (1 sentence), Consequences (2–3 bullets with + / -)
Date everywhere: {self.config.today}
Also add an empty "Rejected Alternatives" section."""
        return self._call_haiku(system, user)

    def _generate_components(self, meta: ProjectMetadata) -> str:
        system = self.DENSE_SYSTEM.format(max_lines=60, today=self.config.today)
        components_text = json.dumps(meta.components[:15], ensure_ascii=False) \
                          if meta.components else "Infer from generated files"
        frontend_files = [f for f in meta.generated_files if 'component' in f.lower()
                          or '/app/' in f.lower()][:20]
        user = f"""Create frontend/components.md:

Project: {meta.project_name}
Frontend: {meta.stack.get('frontend', 'Unknown')}
Styling: {meta.stack.get('styling', 'Unknown')}
Known components: {components_text}
Frontend files: {json.dumps(frontend_files, ensure_ascii=False)}

Must include:
1. Status header (✅, invalidated by: src/components/**, src/app/**/page.tsx, tailwind.config.*)
2. Component inventory table (Name | Path | Purpose | Key Props) — min 3 rows
3. Pages & routing (ASCII tree of src/app/)
4. Styling conventions (compact, key/value format)
5. Gotchas (3–4 items)
6. Update log"""
        return self._call_haiku(system, user)

    def _generate_state(self, meta: ProjectMetadata) -> str:
        system = self.DENSE_SYSTEM.format(max_lines=55, today=self.config.today)
        store_files = [f for f in meta.generated_files if 'store' in f.lower()
                       or 'context' in f.lower()]
        user = f"""Create frontend/state.md:

Project: {meta.project_name}
State management: {meta.stack.get('state', 'Not defined')}
Auth: {meta.stack.get('auth', 'Not defined')}
Store files: {json.dumps(store_files, ensure_ascii=False)}

Must include:
1. Status header (✅, invalidated by: store/**, context/**, lib/store*)
2. State architecture (compact key/value format)
3. Store inventory table (Store | Path | Manages)
4. Zustand pattern (compact code example)
5. React Query pattern (compact, with staleTime/retry)
6. Auth state access (Server vs Client Component, 4 lines each)
7. Gotchas (3 items)
8. Update log"""
        return self._call_haiku(system, user)

    def _generate_api(self, meta: ProjectMetadata) -> str:
        system = self.DENSE_SYSTEM.format(max_lines=70, today=self.config.today)
        api_text = json.dumps(meta.api_routes[:10], ensure_ascii=False) \
                   if meta.api_routes else "Infer from generated API files"
        api_files = [f for f in meta.generated_files if '/api/' in f][:15]
        user = f"""Create backend/api.md:

Project: {meta.project_name}
Backend: {meta.stack.get('backend', 'Unknown')}
Auth: {meta.stack.get('auth', 'Unknown')}
Known routes: {api_text}
API files: {json.dumps(api_files, ensure_ascii=False)}

Must include:
1. Status header (✅, invalidated by: src/app/api/**, middleware.ts, .env*)
2. API structure (ASCII folder tree)
3. Endpoints inventory table (Method | Endpoint | Auth ✅ | Description)
4. Standard route pattern (TypeScript, ~15 lines, auth check first)
5. Auth configuration (compact key/value)
6. Environment variables (bash comments)
7. Gotchas (3 items)
8. Update log"""
        return self._call_haiku(system, user)

    def _generate_database(self, meta: ProjectMetadata) -> str:
        system = self.DENSE_SYSTEM.format(max_lines=65, today=self.config.today)
        models_text = json.dumps(meta.db_models[:8], ensure_ascii=False) \
                      if meta.db_models else "Infer from Prisma schema"
        prisma_files = [f for f in meta.generated_files if 'prisma' in f.lower()][:10]
        user = f"""Create backend/database.md:

Project: {meta.project_name}
ORM: {meta.stack.get('orm', 'Prisma')}
Database: {meta.stack.get('database', 'PostgreSQL')}
DB models: {models_text}
Prisma files: {json.dumps(prisma_files, ensure_ascii=False)}

Must include:
1. Status header (✅, invalidated by: prisma/schema.prisma, new migration)
2. Setup (compact key/value: ORM, Database, Host, Client path)
3. Schema overview: ASCII tree of models + fields + relations
4. ER diagram (text: User ──< Model1)
5. Prisma patterns (code: findMany, create, transaction — compact)
6. Migrations log table (Date | Name | What Changed) — 1 initial row
7. Prisma commands reference (bash, 5 commands)
8. Gotchas (4 items)
9. Update log"""
        return self._call_haiku(system, user)


# =============================================================================
# Integration helper
# =============================================================================

def integrate_into_orchestrator(project_output_dir: str, orchestrator_result: dict) -> dict:
    """
    Call this at the end of your Idea-to-Folder orchestrator, before creating the ZIP.

    Args:
        project_output_dir: Path to the generated project folder
        orchestrator_result: Your orchestrator's result dict
    """
    metadata = ProjectMetadata(
        project_name=orchestrator_result.get("project_name", "Unknown"),
        project_description=orchestrator_result.get("description", ""),
        stack=orchestrator_result.get("stack", {}),
        folder_structure=orchestrator_result.get("folder_structure", ""),
        generated_files=orchestrator_result.get("files", []),
        architecture_decisions=orchestrator_result.get("decisions", []),
        api_routes=orchestrator_result.get("api_routes", []),
        db_models=orchestrator_result.get("db_models", []),
        components=orchestrator_result.get("components", []),
        known_gotchas=orchestrator_result.get("gotchas", []),
        sprint_goal=orchestrator_result.get("sprint_goal", "Initial project setup complete"),
    )
    agent = ContextManagerAgent(project_output_dir=project_output_dir)
    return agent.run(metadata)


# =============================================================================
# Standalone test
# =============================================================================

if __name__ == "__main__":
    test_metadata = ProjectMetadata(
        project_name="TeacherSaaS",
        project_description="AI-powered tool for teachers: worksheet generation + photo-based exam correction",
        stack={
            "frontend": "Next.js 14 (App Router)",
            "styling": "Tailwind CSS v4 + shadcn/ui",
            "backend": "Next.js API Routes",
            "orm": "Prisma 5",
            "database": "PostgreSQL (Supabase)",
            "auth": "NextAuth v5",
            "state": "Zustand + React Query",
        },
        folder_structure="""
teachersaas/
├── src/
│   ├── app/
│   │   ├── (auth)/login/page.tsx
│   │   ├── (dashboard)/
│   │   │   ├── layout.tsx
│   │   │   ├── page.tsx
│   │   │   └── worksheets/page.tsx
│   │   └── api/
│   │       ├── auth/[...nextauth]/route.ts
│   │       └── worksheets/route.ts
│   ├── components/ui/
│   └── lib/prisma.ts
├── prisma/schema.prisma
└── _ai_context/
""",
        generated_files=[
            "src/app/(auth)/login/page.tsx",
            "src/app/(dashboard)/page.tsx",
            "src/app/api/worksheets/route.ts",
            "src/components/ui/button.tsx",
            "src/lib/prisma.ts",
            "prisma/schema.prisma",
            "package.json",
            "tailwind.config.ts",
        ],
        architecture_decisions=[
            "App Router over Pages Router for Server Components",
            "Prisma over Drizzle for TypeScript integration",
            "Supabase as managed PostgreSQL for simple deployment",
        ],
        api_routes=[
            {"method": "GET", "path": "/api/worksheets", "auth": True, "desc": "List all worksheets"},
            {"method": "POST", "path": "/api/worksheets", "auth": True, "desc": "Create worksheet"},
        ],
        db_models=[
            {"name": "User", "fields": ["id", "email", "name", "createdAt"]},
            {"name": "Worksheet", "fields": ["id", "title", "content", "userId", "createdAt"]},
        ],
        known_gotchas=[
            "NextAuth v5 — NOT v4. Breaking changes in session callback",
            "Prisma Client as singleton in lib/prisma.ts — never new PrismaClient() in routes",
            "Supabase: DATABASE_URL (pooled) vs DIRECT_URL (direct) — both needed",
        ],
        sprint_goal="MVP: User auth + worksheet generator functional",
    )

    import tempfile
    with tempfile.TemporaryDirectory() as tmpdir:
        agent = ContextManagerAgent(project_output_dir=tmpdir)
        result = agent.run(test_metadata)
        print(f"\nTest result: {result}")
        print("\nGenerated files:")
        for f in Path(tmpdir).rglob("*.md"):
            print(f"  {f.relative_to(tmpdir)} ({f.stat().st_size} bytes)")
