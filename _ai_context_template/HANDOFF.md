# 🤝 HANDOFF.md — Session-Übergabe
> **Wann nutzen:** Aufgabe ist nicht fertig wenn Session endet.
> **Wann ignorieren:** Aufgabe abgeschlossen → Status: done oder leer.
> **Auto-Load:** Wird in `_SESSION.md` inline geladen wenn `Status: in_progress`.
> **Auto-Reaktion:** ai-session-prep.sh propagiert die ⚠️/🔍/🌐-Felder als Status in _ai_index.md.

---

**Status:** _none_   <!-- in_progress | done | none -->
**Datum:** [YYYY-MM-DD]

## Was läuft
[1-2 Sätze: aktueller Stand]

## Nächster Schritt
[Konkreter erster Task wenn neue Session startet]

## Geänderte Dateien
- [pfad/zu/datei.ts] — [Status: WIP | tested | done]

## ⚠️ Welche Kontextdatei muss aktualisiert werden?
<!-- Format: pfad/zur/datei.md — Begründung -->
<!-- z.B. backend/endpoints.md — neue Login-Route fehlt dort -->
<!-- Setzt ⚠️ in _ai_index.md Datei-Tabelle. Mehrere Zeilen ok. -->
[leer wenn nichts]

## 🔍 Welche Scope-Datei war unvollständig?
<!-- Format: pfad/zur/datei.md — was fehlte -->
<!-- z.B. frontend/components.md — LoginForm nicht dokumentiert -->
<!-- Setzt 🔴 in _ai_index.md (höchste Priorität für nächste Session). -->
[leer wenn nichts]

## 🌐 Welche globalen Abhängigkeiten wurden berührt?
<!-- Format: code/datei.ts — Begründung -->
<!-- z.B. lib/auth.ts — betrifft alle protected routes -->
<!-- Triggert Cascade-Markierung in _ai_index.md (max 5 Dateien). -->
[leer wenn nichts]

## 🧬 Kontext-Triage (vor Session-Cut)
<!-- Ausfüllen wenn Kontext ≥55% oder Session-Cut geplant -->
**MUSS erhalten bleiben:**   <!-- Entscheidungen, Invarianten, "Don't touch" -->
[leer wenn nichts]

**Nur historisch:**           <!-- Was kann sicher vergessen werden -->
[leer wenn nichts]

**Gefährlich zu verlieren:** <!-- Subtile Constraints, mündliche Absprachen -->
[leer wenn nichts]

## Blocker / offene Fragen
[Optional]

---
> Wenn fertig: `Status: done` setzen oder Datei leeren.
