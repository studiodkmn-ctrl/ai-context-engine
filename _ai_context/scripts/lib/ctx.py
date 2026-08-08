#!/usr/bin/env python3
"""ctx.py — Shared helpers for the AI Context Engine scripts (v7).

Importable module (preferred — used by the inline Python heredocs in
ai-context-registry.sh, ai-session-prep.sh, ai-context-doctor.sh and
check_context_hash.sh via `sys.path.insert(0, <this dir>); import ctx`)
AND a small CLI (`python3 ctx.py <cmd> ...`) for standalone/shell use.

Consolidates what used to be 3+ duplicated inline-Python blocks:
  - token estimation (registry.sh, ai-session-prep.sh, doctor.sh est_tokens())
  - ID:/RULE: chunk block + anchor parsing
  - two divergent STOPWORDS sets (registry.sh vs check_context_hash.sh)
  - git-history based freshness (`git_last_touched`, new in v7)
  - synonym expansion for tag generation (new in v7)
"""
from __future__ import annotations

import hashlib
import re
import subprocess
import sys
from pathlib import Path

# ---------------------------------------------------------------------------
# Stopwords — union of ai-context-registry.sh (30 words) and
# check_context_hash.sh's extract_keywords() (14 words), deduplicated.
# MIN_TAG_LEN raised from 3 to 4 chars (v6.x allowed len>2) to kill short
# fragments like "voll" staying borderline — combined with the stopword
# union this removes the "erzeugt"/"schl"-style garbage tags from v6.x.
# ---------------------------------------------------------------------------
STOPWORDS_DE_EN = {
    # from ai-context-registry.sh:61-67
    "the", "and", "for", "ist", "der", "die", "das", "bei", "von", "mit",
    "nicht", "wird", "kann", "alle", "src", "lib", "use", "new", "get",
    "set", "add", "run", "via", "nur", "immer", "oder", "api", "file",
    "node", "statt", "ohne", "nach", "kein", "import", "from", "this",
    "that", "with", "scope", "pattern", "violates", "return", "func",
    "just", "only",
    # from check_context_hash.sh extract_keywords():56-58
    "wird", "kann",
    # additional garbage observed in real registry.yaml output (S5 fix)
    "erzeugt", "voll", "schlecht", "immer", "alle", "hier", "dort",
    "auch", "sind", "sein", "eine", "einer", "einem", "einen",
    # v9-b: "wie" fehlte und matchte fast jeden Vergleichs-Kommentar
    # ("... gleicher Stil wie ...") — entdeckt durch den Prompt-Router-
    # Rauschtest (Anfrage "Wie ist das Wetter..." traf faelschlich einen
    # Treffer, siehe decisions.md).
    "wie",
}

MIN_TAG_LEN = 4

CHUNK_BLOCK_RE = re.compile(r"```\s*\n((?:ID:|RULE:)[\s\S]*?)```", re.MULTILINE)
CHUNK_ID_RE = re.compile(r"(?:ID:|RULE:)\s*(\S+)")
ANCHOR_RE = re.compile(r"<!-- #(\w+) -->\n([\s\S]*?)<!-- /\1 -->", re.MULTILINE)
PRIORITY_RE = re.compile(r"\nP:\s*([123])")
SEEN_RE = re.compile(r"\nseen:\s*(\d{4}-\d{2}-\d{2})")
AT_FILES_RE = re.compile(r"\n@\s*([^\n]+)")


def count_tokens(text: str) -> int:
    """Token estimate: code blocks ~0.35 tok/char, DE/EN prose ~1.8 tok/word.

    Identical formula to what was previously duplicated in
    ai-context-registry.sh:113-117, ai-session-prep.sh count_tokens[_str](),
    and ai-context-doctor.sh est_tokens().
    """
    if not text:
        return 0
    code_blocks = re.findall(r"```[\s\S]*?```", text)
    code_chars = sum(len(b) for b in code_blocks)
    prose = re.sub(r"```[\s\S]*?```", "", text)
    prose_tokens = int(len(prose.split()) * 1.8)
    code_tokens = int(code_chars * 0.35)
    return max(prose_tokens + code_tokens, 0)


def extract_chunk(file_path: str, chunk_id: str) -> str | None:
    """Extract the text between <!-- #id --> ... <!-- /id --> anchors."""
    p = Path(file_path)
    if not p.exists():
        return None
    content = p.read_text(encoding="utf-8")
    m = re.search(
        r"<!-- #" + re.escape(chunk_id) + r" -->\n([\s\S]*?)<!-- /" + re.escape(chunk_id) + r" -->",
        content,
        re.MULTILINE,
    )
    return m.group(1).strip() if m else None


def parse_chunk_blocks(content: str) -> list[str]:
    """Return raw ID:/RULE: code-fence block bodies (without fences)."""
    return CHUNK_BLOCK_RE.findall(content)


def chunk_id_of(block: str) -> str | None:
    m = CHUNK_ID_RE.search(block)
    return m.group(1) if m else None


def chunk_priority_of(block: str) -> int:
    m = PRIORITY_RE.search(block)
    return int(m.group(1)) if m else 2


def parse_registry(path: str) -> dict:
    """Minimal line-based registry.yaml parser (no PyYAML dependency).

    Returns {"chunks": [ {id, type, priority, file, anchor, tags, tokens,
    hash, updated, seen, code_touched, status}, ... ]}.
    Tolerant of missing v7 fields (seen/code_touched/status) for chunks
    written by older ai-context-registry.sh versions.
    """
    chunks: list[dict] = []
    current: dict = {}
    p = Path(path)
    if not p.exists():
        return {"chunks": chunks}
    with p.open(encoding="utf-8") as f:
        for line in f:
            s = line.strip()
            if s.startswith("- id:"):
                if current.get("id"):
                    chunks.append(current)
                current = {
                    "id": s.split(":", 1)[1].strip(),
                    "type": "",
                    "priority": 2,
                    "file": "",
                    "anchor": "",
                    "tags": [],
                    "tokens": 0,
                    "hash": "",
                    "updated": "",
                    "seen": "",
                    "code_touched": "",
                    "status": "",
                }
            elif not current:
                continue
            elif s.startswith("type:"):
                current["type"] = s.split(":", 1)[1].strip()
            elif s.startswith("priority:"):
                try:
                    current["priority"] = int(s.split(":", 1)[1].strip())
                except ValueError:
                    pass
            elif s.startswith("file:"):
                current["file"] = s.split(":", 1)[1].strip()
            elif s.startswith("anchor:"):
                current["anchor"] = s.split(":", 1)[1].strip()
            elif s.startswith("tags:"):
                raw = s.split(":", 1)[1].strip().strip("[]")
                current["tags"] = [t.strip() for t in raw.split(",") if t.strip()]
            elif s.startswith("tokens:"):
                try:
                    current["tokens"] = int(s.split(":", 1)[1].strip())
                except ValueError:
                    pass
            elif s.startswith("hash:"):
                current["hash"] = s.split(":", 1)[1].strip().strip('"')
            elif s.startswith("updated:"):
                current["updated"] = s.split(":", 1)[1].strip()
            elif s.startswith("seen:"):
                current["seen"] = s.split(":", 1)[1].strip()
            elif s.startswith("code_touched:"):
                current["code_touched"] = s.split(":", 1)[1].strip()
            elif s.startswith("status:"):
                current["status"] = s.split(":", 1)[1].strip()
        if current.get("id"):
            chunks.append(current)
    return {"chunks": chunks}


def git_last_touched(paths: list[str], cwd: str | None = None) -> str | None:
    """Max `git log -1 --format=%as -- <path>` across several paths.

    Returns None if git is unavailable or none of the paths have history
    (e.g. paths don't exist / repo has no commits touching them).
    """
    dates: list[str] = []
    for path in paths:
        path = path.strip()
        if not path:
            continue
        try:
            out = subprocess.run(
                ["git", "log", "-1", "--format=%as", "--", path],
                cwd=cwd, capture_output=True, text=True, timeout=5,
            )
        except (OSError, subprocess.SubprocessError):
            continue
        date = out.stdout.strip()
        if date:
            dates.append(date)
    return max(dates) if dates else None


def _looks_like_path(token: str) -> bool:
    """True for plausible file paths, False for prose like "alle API routes".

    The `@` line mixes real paths ("src/lib/auth.ts") with free-text hints
    ("alle API routes", "alle DB-Zugriffe") — only the former are useful
    for git_last_touched()/orphan-detection.
    """
    token = token.strip()
    if not token:
        return False
    return "/" in token or bool(re.search(r"\.\w{1,4}$", token))


def parse_at_files(chunk_text: str) -> list[str]:
    """Extract plausible file paths from the `@ file1, file2, ...` line."""
    m = AT_FILES_RE.search(chunk_text)
    if not m:
        return []
    raw = m.group(1)
    return [f.strip() for f in raw.split(",") if _looks_like_path(f)]


def extract_seen_field(chunk_text: str) -> str | None:
    m = SEEN_RE.search(chunk_text)
    return m.group(1) if m else None


def load_synonyms(path: str) -> dict[str, list[str]]:
    """Parse synonyms.txt: `word=alias1,alias2` per line, '#' comments."""
    out: dict[str, list[str]] = {}
    p = Path(path)
    if not p.exists():
        return out
    for line in p.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        word, _, aliases = line.partition("=")
        word = word.strip().lower()
        alias_list = [a.strip().lower() for a in aliases.split(",") if a.strip()]
        if word and alias_list:
            out[word] = alias_list
    return out


def expand_tags(tags: set[str], synonyms: dict[str, list[str]]) -> set[str]:
    """Add synonym aliases for any tag that matches a synonyms.txt key
    (in either direction: word->aliases or alias->word)."""
    expanded = set(tags)
    for word, aliases in synonyms.items():
        if word in tags:
            expanded.update(aliases)
        elif any(a in tags for a in aliases):
            expanded.add(word)
    return expanded


def extract_tags_from_chunk(chunk_id: str, text: str, synonyms: dict[str, list[str]] | None = None) -> list[str]:
    """Tag extraction used by ai-context-registry.sh --scan.

    Pulls words from the →/@/scope: label lines + the chunk id itself,
    filters stopwords + MIN_TAG_LEN, optionally expands via synonyms,
    returns top-8 alphabetically sorted (unchanged v6.x sort behaviour).
    """
    # Umlaute (äöüß) im Wort-Zeichensatz — sonst zerschneidet die Regex z.B.
    # "schlägt" in "schl" + "gt" (der genaue S5-Bug: abgeschnittene Woerter).
    WORD_RE = re.compile(r"[a-zA-Zäöüß][a-zA-Z0-9äöüß_-]{2,}")
    words: set[str] = set()
    for label_pattern in (r"→\s*([^\n]+)", r"@\s*([^\n]+)", r"scope:\s*([^\n]+)"):
        lm = re.search(label_pattern, text)
        if lm:
            words.update(WORD_RE.findall(lm.group(1).lower()))
    words.update(p for p in re.split(r"[_\-]", chunk_id.lower()) if len(p) > 2)

    filtered = {
        w for w in words
        if w not in STOPWORDS_DE_EN and len(w) >= MIN_TAG_LEN and w.replace("-", "").isalpha()
    }
    if synonyms:
        filtered = expand_tags(filtered, synonyms)
        # re-filter in case expansion introduced a stopword/short alias
        filtered = {
            w for w in filtered
            if w not in STOPWORDS_DE_EN and len(w) >= MIN_TAG_LEN and w.replace("-", "").isalpha()
        }
    return sorted(filtered)[:8]


def list_drawer_indexes(drawers_yaml_path: str) -> list[str]:
    """Return the `index:` value of every drawer in drawers.yaml.

    Minimal parser for the flat drawers.yaml schema (no PyYAML dependency,
    see decisions.md#drawers_yaml_parsing).
    """
    p = Path(drawers_yaml_path)
    if not p.exists():
        return []
    indexes: list[str] = []
    for line in p.read_text(encoding="utf-8").splitlines():
        s = line.strip()
        if s.startswith("index:"):
            indexes.append(s.split(":", 1)[1].strip())
    return indexes


def load_knowledge_manifest(manifest_path: str) -> list[dict]:
    """Parse knowledge.manifest.yaml (v9-a) — single source of truth for
    which files are "knowledge files", replacing the hardcoded
    KNOWLEDGE_FILES lists formerly duplicated in locate.ts, ai-context-
    registry.sh, ai-context-doctor.sh and hooks/post-commit (see
    decisions.md#knowledge_manifest).

    Minimal line-based parser, same style as list_drawer_indexes — no
    PyYAML dependency. Each entry: {path, type, markers: list[str],
    max_entries: int|None, archive: str|None, seed: bool}.
    """
    p = Path(manifest_path)
    if not p.exists():
        return []
    entries: list[dict] = []
    cur: dict | None = None

    def flush() -> None:
        if cur and cur.get("path"):
            entries.append(cur)

    for line in p.read_text(encoding="utf-8").splitlines():
        s = line.strip()
        if s.startswith("- path:"):
            flush()
            cur = {"path": s.split(":", 1)[1].strip(), "type": "", "markers": [],
                   "max_entries": None, "archive": None, "seed": False}
            continue
        if cur is None:
            continue
        if s.startswith("type:"):
            cur["type"] = s.split(":", 1)[1].strip()
        elif s.startswith("markers:"):
            raw = s.split(":", 1)[1].strip().strip("[]")
            cur["markers"] = [m.strip() for m in raw.split(",") if m.strip()]
        elif s.startswith("max_entries:"):
            try:
                cur["max_entries"] = int(s.split(":", 1)[1].strip())
            except ValueError:
                pass
        elif s.startswith("archive:"):
            cur["archive"] = s.split(":", 1)[1].strip()
        elif s.startswith("seed:"):
            cur["seed"] = s.split(":", 1)[1].strip().lower() == "true"
    flush()
    return entries


def _main(argv: list[str]) -> int:
    if len(argv) < 2:
        print("Usage: ctx.py <count_tokens|extract_chunk|git_last_touched|"
              "list_drawer_indexes|list_knowledge_files> ...", file=sys.stderr)
        return 1
    cmd = argv[1]
    if cmd == "count_tokens":
        text = sys.stdin.read() if len(argv) < 3 else argv[2]
        print(count_tokens(text))
    elif cmd == "extract_chunk":
        if len(argv) < 4:
            print("Usage: ctx.py extract_chunk <file> <chunk_id>", file=sys.stderr)
            return 1
        result = extract_chunk(argv[2], argv[3])
        print(result if result is not None else "")
    elif cmd == "git_last_touched":
        result = git_last_touched(argv[2:])
        print(result or "")
    elif cmd == "list_drawer_indexes":
        if len(argv) < 3:
            print("Usage: ctx.py list_drawer_indexes <drawers.yaml>", file=sys.stderr)
            return 1
        for idx in list_drawer_indexes(argv[2]):
            print(idx)
    elif cmd == "list_knowledge_files":
        if len(argv) < 3:
            print("Usage: ctx.py list_knowledge_files <manifest.yaml> [--seed-only]", file=sys.stderr)
            return 1
        seed_only = "--seed-only" in argv[3:]
        for entry in load_knowledge_manifest(argv[2]):
            if seed_only and not entry["seed"]:
                continue
            print(entry["path"])
    else:
        print(f"Unknown command: {cmd}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(_main(sys.argv))
