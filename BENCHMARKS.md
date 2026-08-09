# BENCHMARKS.md — gemessene Zahlen
> Automatisch generiert von `bench/ai-bench.py` aus `bench/results.jsonl`.
> 28 Läufe insgesamt, nach Phase getrennt (Mischung aus Vorher/
> Nachher wäre eine Zahl, die nichts aussagt).

**Gemessen wird Effizienz** — Kosten, Turns, Tokens bis zur Antwort.
**Korrektheit taugt hier nicht als Beleg**: die Fixture kommentiert ihre
Bugs im Klartext (`// BUG #1: Auth-Check fehlt komplett`), bei drei der
vier Tasks erreichen daher beide Arme 100 % — der Score zeigt dort nur,
dass die Aufgabe lösbar war. Wo die Scores auseinandergehen
(`vocab_mismatch`, 67 % vs 33 %), ist n=3 bei binärem Ausgang zu klein:
2 von 3 gegen 1 von 3 richtig ist Zufallsstreuung, keine Aussage.

**Kosten ($) sind die Leitmetrik**, nicht Input-Tokens: `cache_read` ist
deutlich billiger als `cache_creation`, eine summierte Token-Zahl kann
also in die falsche Richtung zeigen.

## Phase `v9d-baseline`

| Task | Arm | n | Ø $ | Ø cache_creation | Ø cache_read | Ø Turns | Ø Score |
|---|---|---|---|---|---|---|---|
| fixture_5bugs | with_system | 1 | 0.4839 | — | (162032 ges.) | 12.0 | 100% |
| fixture_5bugs | without_system | 1 | 0.4115 | — | (141906 ges.) | 12.0 | 100% |
| locate_read_guard | with_system | 1 | 0.2703 | — | (206732 ges.) | 4.0 | 100% |
| locate_read_guard | without_system | 1 | 0.2817 | — | (282271 ges.) | 6.0 | 100% |

### Delta `v9d-baseline` (mit System − ohne System)

| Task | Δ Kosten $ | Δ % | Δ Turns | Bewertung |
|---|---|---|---|---|
| fixture_5bugs | +0.0724 | +17.6% | +0.0 | System kostet mehr |
| locate_read_guard | -0.0114 | -4.0% | -2.0 | System spart |

## Phase `v10-repaired`

| Task | Arm | n | Ø $ | Ø cache_creation | Ø cache_read | Ø Turns | Ø Score |
|---|---|---|---|---|---|---|---|
| fix_one_symptom | with_system | 3 | 0.2541 | 35144 | 121776 | 3.7 | 100% |
| fix_one_symptom | without_system | 3 | 0.2166 | 29444 | 108266 | 4.0 | 100% |
| fixture_5bugs | with_system | 3 | 0.3287 | 41014 | 141521 | 11.3 | 100% |
| fixture_5bugs | without_system | 3 | 0.3685 | 45200 | 168873 | 14.0 | 100% |
| locate_read_guard | with_system | 3 | 0.2911 | 35665 | 203917 | 5.7 | 100% |
| locate_read_guard | without_system | 3 | 0.3258 | 37558 | 263752 | 6.0 | 100% |
| vocab_mismatch | with_system | 3 | 0.2428 | 34404 | 103802 | 2.7 | 67% |
| vocab_mismatch | without_system | 3 | 0.1583 | 24834 | 17981 | 1.0 | 33% |

### Delta `v10-repaired` (mit System − ohne System)

| Task | Δ Kosten $ | Δ % | Δ Turns | Bewertung |
|---|---|---|---|---|
| fix_one_symptom | +0.0376 | +17.3% | -0.3 | System kostet mehr |
| fixture_5bugs | -0.0398 | -10.8% | -2.7 | System spart |
| locate_read_guard | -0.0347 | -10.6% | -0.3 | System spart |
| vocab_mismatch | +0.0844 | +53.3% | +1.7 | System kostet mehr |
