# 📐 ADR-Anleitung
> Ausgelagert aus `decisions.md` (Overflow-Regel, 600-Token-Split).
> Nur laden wenn eine neue ADR geschrieben wird — nicht Teil des normalen Routings.

---

## Wann eine neue ADR schreiben?
```
- Wenn eine Technologie gewählt oder ausgetauscht wird (ORM, Auth, State, Hosting).
- Wenn ein Pattern eingeführt wird, das projektweit gelten soll.
- Wenn ein vorheriger Ansatz bewusst verworfen wird.
- Faustregel: Wenn zukünftige Claude-Sessions fragen würden "warum ist das so?" → ADR.
```

## ADR Template
```
### ADR-[NR]: [Short Title]
**Date:** YYYY-MM-DD  |  **Status:** Accepted / Superseded by ADR-[NR] / In Discussion

**Context:** [Why did this decision need to be made?]
**Decision:** [What was decided?]
**Consequences:**
  + [Advantage]
  - [Trade-off]
```

## Rejected-Alternative-Template
```
### [Approach] — Rejected YYYY-MM-DD
Tried:    [What was attempted]
Problem:  [Why it didn't work]
Solution: [What was done instead]
Remember: [Concrete hint for the future]
```
