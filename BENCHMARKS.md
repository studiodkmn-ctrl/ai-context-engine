# BENCHMARKS.md — gemessene Zahlen (v9-d Beweis-Harness)
> Automatisch generiert von `bench/ai-bench.py` aus `bench/results.jsonl`.
> Stand: 4 Läufe insgesamt. **Vorläufige Stichprobe** — bei
> kleinem `n` sind Werte verrauscht, siehe `n=` Spalte pro Zeile. Mehr
> Läufe: `python3 bench/ai-bench.py --repeat 5`.

| Task | Arm | Modell | n | Ø Kosten $ | Ø Input-Tok | Ø Output-Tok | Ø Turns | Ø Score |
|---|---|---|---|---|---|---|---|---|
| fixture_5bugs | with_system | sonnet | 1 | 0.4839 | 162032 | 2803 | 12.0 | 100% |
| fixture_5bugs | without_system | sonnet | 1 | 0.4115 | 141906 | 2734 | 12.0 | 100% |
| locate_read_guard | with_system | sonnet | 1 | 0.2703 | 206732 | 708 | 4.0 | 100% |
| locate_read_guard | without_system | sonnet | 1 | 0.2817 | 282271 | 1301 | 6.0 | 100% |
