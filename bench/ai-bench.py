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


def run_task(task: dict, model: str, claude_bin: str, results_path: Path, phase: str) -> None:
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
            cache_creation = usage.get("cache_creation_input_tokens", 0)
            cache_read = usage.get("cache_read_input_tokens", 0)
            input_tokens = cache_creation + cache_read
            output_tokens = usage.get("output_tokens", 0)
            hit, total = grade(data.get("result", ""), task.get("expect_any_of_each", []))
            record = {
                "ts": datetime.now(timezone.utc).isoformat(),
                "phase": phase,
                "task_id": task["id"],
                "arm": arm_label,
                "model": model,
                "cost_usd": data.get("total_cost_usd"),
                "num_turns": data.get("num_turns"),
                "duration_api_ms": data.get("duration_api_ms"),
                "input_tokens": input_tokens,
                "cache_creation": cache_creation,
                "cache_read": cache_read,
                "output_tokens": output_tokens,
                "score_hit": hit,
                "score_total": total,
                "is_error": data.get("is_error", False),
            }
        except Exception as e:
            record = {
                "ts": datetime.now(timezone.utc).isoformat(),
                "phase": phase,
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

    # Zeilen ohne phase stammen aus dem ersten Lauf vor Einfuehrung des Feldes.
    for r in rows:
        r.setdefault("phase", "v9d-baseline")

    groups: dict[tuple, list[dict]] = defaultdict(list)
    for r in rows:
        if r.get("error"):
            continue
        groups[(r["phase"], r["task_id"], r["arm"], r["model"])].append(r)

    def avg(recs, key):
        return sum(r.get(key) or 0 for r in recs) / len(recs)

    def avg_score(recs):
        scored = [r for r in recs if r.get("score_total")]
        if not scored:
            return 0.0
        return sum(r["score_hit"] / r["score_total"] for r in scored) / len(scored)

    # Phasen in der Reihenfolge ihres ersten Auftretens
    phases = []
    for r in rows:
        if r["phase"] not in phases:
            phases.append(r["phase"])

    total_runs = sum(len(v) for v in groups.values())
    lines = [
        "# BENCHMARKS.md — gemessene Zahlen",
        "> Automatisch generiert von `bench/ai-bench.py` aus `bench/results.jsonl`.",
        f"> {total_runs} Läufe insgesamt, nach Phase getrennt (Mischung aus Vorher/",
        "> Nachher wäre eine Zahl, die nichts aussagt).",
        "",
        "**Gemessen wird Effizienz** — Kosten, Turns, Tokens bis zur Antwort.",
        "**Korrektheit taugt hier nicht als Beleg**: die Fixture kommentiert ihre",
        "Bugs im Klartext (`// BUG #1: Auth-Check fehlt komplett`), bei drei der",
        "vier Tasks erreichen daher beide Arme 100 % — der Score zeigt dort nur,",
        "dass die Aufgabe lösbar war. Wo die Scores auseinandergehen",
        "(`vocab_mismatch`, 67 % vs 33 %), ist n=3 bei binärem Ausgang zu klein:",
        "2 von 3 gegen 1 von 3 richtig ist Zufallsstreuung, keine Aussage.",
        "",
        "**Kosten ($) sind die Leitmetrik**, nicht Input-Tokens: `cache_read` ist",
        "deutlich billiger als `cache_creation`, eine summierte Token-Zahl kann",
        "also in die falsche Richtung zeigen.",
        "",
    ]

    for phase in phases:
        keys = sorted(k for k in groups if k[0] == phase)
        if not keys:
            continue
        lines += [
            f"## Phase `{phase}`",
            "",
            "| Task | Arm | n | Ø $ | Ø cache_creation | Ø cache_read | Ø Turns | Ø Score |",
            "|---|---|---|---|---|---|---|---|",
        ]
        for k in keys:
            recs = groups[k]
            _, task_id, arm, _model = k
            cc = avg(recs, "cache_creation")
            cr = avg(recs, "cache_read")
            # Altzeilen ohne getrennte Felder: nur die Summe ausweisen.
            cc_s = f"{cc:.0f}" if cc else "—"
            cr_s = f"{cr:.0f}" if cr else f"({avg(recs, 'input_tokens'):.0f} ges.)"
            lines.append(
                f"| {task_id} | {arm} | {len(recs)} | {avg(recs, 'cost_usd'):.4f} | "
                f"{cc_s} | {cr_s} | {avg(recs, 'num_turns'):.1f} | {avg_score(recs):.0%} |"
            )
        lines.append("")

        # Delta je Task: mit System − ohne System
        lines += [
            f"### Delta `{phase}` (mit System − ohne System)",
            "",
            "| Task | Δ Kosten $ | Δ % | Δ Turns | Bewertung |",
            "|---|---|---|---|---|",
        ]
        tasks_in_phase = sorted({k[1] for k in keys})
        for task_id in tasks_in_phase:
            w = groups.get((phase, task_id, "with_system", "sonnet"))
            o = groups.get((phase, task_id, "without_system", "sonnet"))
            if not w or not o:
                continue
            cw, co = avg(w, "cost_usd"), avg(o, "cost_usd")
            d_cost = cw - co
            d_pct = (d_cost / co * 100) if co else 0.0
            d_turns = avg(w, "num_turns") - avg(o, "num_turns")
            verdict = "System spart" if d_cost < 0 else "System kostet mehr"
            lines.append(
                f"| {task_id} | {d_cost:+.4f} | {d_pct:+.1f}% | {d_turns:+.1f} | {verdict} |"
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
    # --phase trennt Messreihen (z.B. vor/nach einem Umbau). Ohne das mittelt
    # der Report ueber alle je gelaufenen Zeilen — eine Zahl, die nichts sagt.
    ap.add_argument("--phase", default="unlabeled")
    args = ap.parse_args()

    claude_bin = find_claude_binary()
    tasks = parse_tasks_yaml(Path(args.tasks))
    results_path = Path(args.results)
    results_path.parent.mkdir(parents=True, exist_ok=True)

    print(f"🧪 ai-bench — {len(tasks)} Task(s) × 2 Arme × {args.repeat}x, Modell {args.model}",
          file=sys.stderr)
    for task in tasks:
        for _ in range(args.repeat):
            run_task(task, args.model, claude_bin, results_path, args.phase)

    generate_report(results_path, Path(args.out))
    print(f"✅ BENCHMARKS.md aktualisiert: {args.out}", file=sys.stderr)


if __name__ == "__main__":
    main()
