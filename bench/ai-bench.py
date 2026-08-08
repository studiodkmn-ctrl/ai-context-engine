#!/usr/bin/env python3
"""ai-bench.py — Beweis-Harness fuer die AI Context Engine (v9-d).

Fuehrt jede Task aus bench/tasks.yaml zweimal headless aus (Arm A: Projekt
mit _ai_context/, Arm B: gleiche Kopie ohne System) und schreibt jeden Lauf
als eine Zeile nach bench/results.jsonl (append-only — akkumuliert ueber
beliebig viele kuenftige Laeufe). BENCHMARKS.md wird danach aus dem
GESAMTEN results.jsonl neu generiert, nicht nur aus dem aktuellen Lauf.

Ruft den echten claude-Binary direkt per subprocess auf (kein Shell dazwischen)
-- das umgeht bewusst den in ~/.zshrc definierten `claude`-Wrapper (druckt vor
jedem Aufruf einen SessionStart-Banner, der --output-format json bricht, wenn
man ihn ueber eine interaktive Shell aufruft).

Usage:
  python3 bench/ai-bench.py [--model sonnet] [--tasks bench/tasks.yaml]
                             [--out BENCHMARKS.md] [--results bench/results.jsonl]
                             [--repeat 1]
"""
from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
import sys
import tempfile
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path

STRIP_FOR_ARM_B = ["_ai_context", "_ai_context_template", "CLAUDE.md", ".claude", "hooks"]
ALLOWED_TOOLS = "Read Grep Glob Bash"
COPY_IGNORE = shutil.ignore_patterns("node_modules", ".git", "__pycache__", "*.pyc")


def find_claude_binary() -> str:
    found = shutil.which("claude")
    if found:
        return found
    for cand in ("~/.local/bin/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude"):
        p = Path(cand).expanduser()
        if p.exists():
            return str(p)
    raise SystemExit("claude-Binary nicht gefunden (weder PATH noch bekannte Fallback-Pfade).")


def parse_tasks_yaml(path: Path) -> list[dict]:
    """Minimaler Parser fuer das flache tasks.yaml-Schema (kein PyYAML,
    gleiche Philosophie wie ctx.py::load_knowledge_manifest)."""
    tasks: list[dict] = []
    cur: dict | None = None
    in_expect = False
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.rstrip()
        stripped = line.strip()
        if stripped.startswith("#") or not stripped:
            continue
        if stripped.startswith("- id:"):
            if cur:
                tasks.append(cur)
            cur = {"id": stripped.split(":", 1)[1].strip(), "expect_any_of_each": []}
            in_expect = False
            continue
        if cur is None:
            continue
        indent = len(line) - len(line.lstrip())
        if stripped.startswith("project:"):
            cur["project"] = stripped.split(":", 1)[1].strip()
            in_expect = False
        elif stripped.startswith("prompt:"):
            val = stripped.split(":", 1)[1].strip()
            if val == ">-":
                cur["_prompt_multiline"] = True
                cur["prompt"] = ""
            else:
                cur["prompt"] = val.strip('"').strip("'")
            in_expect = False
        elif stripped.startswith("expect_any_of_each:"):
            in_expect = True
        elif stripped.startswith("- [") and in_expect:
            items = re.findall(r'"([^"]*)"', stripped)
            cur["expect_any_of_each"].append(items)
        elif cur.get("_prompt_multiline") and indent >= 6 and not stripped.startswith("-"):
            cur["prompt"] = (cur["prompt"] + " " + stripped).strip()
    if cur:
        tasks.append(cur)
    for t in tasks:
        t.pop("_prompt_multiline", None)
    return tasks


def make_arm_copy(project_dir: Path, strip_system: bool) -> Path:
    tmp = Path(tempfile.mkdtemp(prefix="aictx-bench-"))
    dest = tmp / "proj"
    shutil.copytree(project_dir, dest, ignore=COPY_IGNORE)
    if strip_system:
        for name in STRIP_FOR_ARM_B:
            p = dest / name
            if p.exists():
                shutil.rmtree(p) if p.is_dir() else p.unlink()
    return dest


def run_claude(claude_bin: str, cwd: Path, prompt: str, model: str) -> dict:
    proc = subprocess.run(
        [
            claude_bin, "-p", prompt,
            "--model", model,
            "--output-format", "json",
            "--permission-mode", "bypassPermissions",
            "--allowedTools", ALLOWED_TOOLS,
        ],
        cwd=str(cwd), capture_output=True, text=True, timeout=300,
    )
    return json.loads(proc.stdout)


def grade(result_text: str, expect_any_of_each: list[list[str]]) -> tuple[int, int]:
    if not expect_any_of_each:
        return (0, 0)
    hay = (result_text or "").lower()
    hit = sum(1 for group in expect_any_of_each if any(kw.lower() in hay for kw in group))
    return (hit, len(expect_any_of_each))


def run_task(task: dict, model: str, claude_bin: str, results_path: Path) -> None:
    project_dir = Path(task["project"])
    if not project_dir.exists():
        print(f"  ⚠️  {task['id']}: Projekt nicht gefunden: {project_dir}", file=sys.stderr)
        return

    for arm_label, strip_system in (("with_system", False), ("without_system", True)):
        arm_dir = make_arm_copy(project_dir, strip_system)
        try:
            print(f"  ▶ {task['id']} [{arm_label}, {model}] ...", file=sys.stderr)
            data = run_claude(claude_bin, arm_dir, task["prompt"], model)
            usage = data.get("usage", {})
            input_tokens = (usage.get("cache_creation_input_tokens", 0) +
                             usage.get("cache_read_input_tokens", 0))
            output_tokens = usage.get("output_tokens", 0)
            hit, total = grade(data.get("result", ""), task.get("expect_any_of_each", []))
            record = {
                "ts": datetime.now(timezone.utc).isoformat(),
                "task_id": task["id"],
                "arm": arm_label,
                "model": model,
                "cost_usd": data.get("total_cost_usd"),
                "num_turns": data.get("num_turns"),
                "duration_api_ms": data.get("duration_api_ms"),
                "input_tokens": input_tokens,
                "output_tokens": output_tokens,
                "score_hit": hit,
                "score_total": total,
                "is_error": data.get("is_error", False),
            }
        except Exception as e:
            record = {
                "ts": datetime.now(timezone.utc).isoformat(),
                "task_id": task["id"], "arm": arm_label, "model": model,
                "error": str(e),
            }
            print(f"    ❌ Fehler: {e}", file=sys.stderr)
        finally:
            shutil.rmtree(arm_dir.parent, ignore_errors=True)

        with results_path.open("a", encoding="utf-8") as f:
            f.write(json.dumps(record, ensure_ascii=False) + "\n")


def generate_report(results_path: Path, out_path: Path) -> None:
    if not results_path.exists():
        return
    rows = []
    for line in results_path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            rows.append(json.loads(line))
        except Exception:
            continue

    groups: dict[tuple, list[dict]] = defaultdict(list)
    for r in rows:
        if r.get("error"):
            continue
        groups[(r["task_id"], r["arm"], r["model"])].append(r)

    total_runs = sum(len(v) for v in groups.values())
    lines = [
        "# BENCHMARKS.md — gemessene Zahlen (v9-d Beweis-Harness)",
        "> Automatisch generiert von `bench/ai-bench.py` aus `bench/results.jsonl`.",
        f"> Stand: {total_runs} Läufe insgesamt. **Vorläufige Stichprobe** — bei",
        "> kleinem `n` sind Werte verrauscht, siehe `n=` Spalte pro Zeile. Mehr",
        "> Läufe: `python3 bench/ai-bench.py --repeat 5`.",
        "",
        "| Task | Arm | Modell | n | Ø Kosten $ | Ø Input-Tok | Ø Output-Tok | Ø Turns | Ø Score |",
        "|---|---|---|---|---|---|---|---|---|",
    ]
    for (task_id, arm, model), recs in sorted(groups.items()):
        n = len(recs)
        avg_cost = sum(r.get("cost_usd") or 0 for r in recs) / n
        avg_in = sum(r.get("input_tokens") or 0 for r in recs) / n
        avg_out = sum(r.get("output_tokens") or 0 for r in recs) / n
        avg_turns = sum(r.get("num_turns") or 0 for r in recs) / n
        scored = [r for r in recs if r.get("score_total")]
        avg_score = (sum(r["score_hit"] / r["score_total"] for r in scored) / len(scored)
                     if scored else 0.0)
        lines.append(
            f"| {task_id} | {arm} | {model} | {n} | {avg_cost:.4f} | "
            f"{avg_in:.0f} | {avg_out:.0f} | {avg_turns:.1f} | {avg_score:.0%} |"
        )
    lines.append("")
    out_path.write_text("\n".join(lines), encoding="utf-8")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", default="sonnet")
    ap.add_argument("--tasks", default=str(Path(__file__).parent / "tasks.yaml"))
    ap.add_argument("--out", default=str(Path(__file__).parent.parent / "BENCHMARKS.md"))
    ap.add_argument("--results", default=str(Path(__file__).parent / "results.jsonl"))
    ap.add_argument("--repeat", type=int, default=1)
    args = ap.parse_args()

    claude_bin = find_claude_binary()
    tasks = parse_tasks_yaml(Path(args.tasks))
    results_path = Path(args.results)
    results_path.parent.mkdir(parents=True, exist_ok=True)

    print(f"🧪 ai-bench — {len(tasks)} Task(s) × 2 Arme × {args.repeat}x, Modell {args.model}",
          file=sys.stderr)
    for task in tasks:
        for _ in range(args.repeat):
            run_task(task, args.model, claude_bin, results_path)

    generate_report(results_path, Path(args.out))
    print(f"✅ BENCHMARKS.md aktualisiert: {args.out}", file=sys.stderr)


if __name__ == "__main__":
    main()
