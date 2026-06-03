# 🏛️ Architecture Decision Records (ADRs)
**Status:** ✅ Fresh · **Updated:** [DATE] · **Invalidated by:** `package.json`, `requirements.txt` changes (new lib = potential new decision)

> Claude: Load this file for refactoring, new feature planning, or "why was X built this way?" questions.
> **Writeback:** Neue ADR sofort anlegen wenn Architekturentscheidung getroffen wird.

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
**Date:** [DATE]  |  **Status:** Accepted / Superseded by ADR-[NR] / In Discussion

**Context:** [Why did this decision need to be made?]
**Decision:** [What was decided?]
**Consequences:**
  + [Advantage]
  - [Trade-off]
```

---

## Decisions

### ADR-001: [ENTSCHEIDUNG EINTRAGEN]
**Date:** [DATE] | **Status:** Accepted

**Context:** [Warum musste diese Entscheidung getroffen werden?]
**Decision:** [Was wurde entschieden?]
**Consequences:**
  + [Vorteil]
  - [Trade-off]

---

## ❌ Rejected Alternatives
> So Claude (and you) don't fall into the same trap again.

```
### [Approach] — Rejected [DATE]
Tried:    [What was attempted]
Problem:  [Why it didn't work]
Solution: [What was done instead]
Remember: [Concrete hint for the future]
```

---

## 📝 Update Log

### [DATE] — Initial setup
- ADR file created, first decisions pending
