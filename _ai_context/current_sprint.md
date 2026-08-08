# 🏃 Current Sprint
**Status:** 🟢 Fresh · **Updated:** 2026-08-06

> Claude: Load this file when unclear where we stand or which tasks are open.
> After each completed task: check off here + add a line to Recent Changes
> in `_temp_notes.md` (this file stays lean — no full Daily Log dump here).

---

## 🎯 Sprint Goal
```
v8 ist geshippt (Pro-Rollout, Self-Update, Self-Healing). Aktuell:
Repo-Hygiene — Doctor-Warnungen auf 0, Pro global + auf allen registrierten
Projekten aktiv, keine stillen No-Ops mehr in Kernmechanismen.
```

---

## 📋 Tasks

### ✅ Done (2026-08-06)
- [x] Pro-Edition global + auf allen 9 registrierten Projekten installiert
- [x] Auto-Invalidierung-Bug (seit v5 wirkungslos) gefixt + E2E-verifiziert
- [x] Drawer-Split lässt Original-Datei + drawers.yaml-Pointer nicht mehr verwaisen
- [x] memory_save (`note`) wächst nicht mehr unbegrenzt in `_temp_notes.md`
- [x] Demo-Boilerplate (`test-kontext`-Restpfade) aus Kontextdateien entfernt

### 📋 Open
- [ ] Ollama-Client/Server-Versionsdrift beheben (Client 0.22.1 vs Server 0.19.0)
- [ ] `decisions.md`-Wachstum beobachten (aktuell knapp unter 600-Token-Grenze)

---

## 🧠 Important Context for Claude
```
Do not touch:  ai-context-drawer.sh split_domain_file() löscht jetzt bewusst
               das Original nach dem Split (rm -f "$abs_file") — kein Rückbau,
               das war der Bugfix.
```

---
> WRITEBACK RULE: Abgeschlossene Tasks hierher, ausführliche Änderungen →
> `_temp_notes.md` Recent Changes (max 5, auto-getrimmt).
