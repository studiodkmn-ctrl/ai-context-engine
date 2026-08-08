# 🔒 Security — ai-context-engine
> **Max 10 Regeln. Code-Format. Laden bei API/Auth-Tasks.**
> Aktualisiert: 2026-08-09
> P: 1=kritisch (nie löschen) | 2=wichtig (default) | 3=nice-to-know (zuerst archiviert)

## Regeln

> Noch keine projekteigenen Security-Regeln — die Demo-Inhalte (auth_first,
> no_secret_frontend, input_validation, scope_to_user, error_format) waren
> unveränderte Next.js-Beispiele aus dem Template und beschrieben nicht
> diese Engine. Entfernt in V10 R1, siehe decisions.md#demo_content.
> Sie leben unverändert in `_ai_context_template/security.md` weiter, wo
> sie als Startpunkt für neue Projekte hingehören.

```
RULE: _template
P: 2
scope: [wo die Regel gilt]
pattern:
  [Code-Beispiel: so ist es richtig]
violates: [was der typische Verstoß ist]
```

> REGELN: P1-Regeln niemals löschen. Überlauf >10 → P3 zuerst, dann prüfe ob älteste P2-Regel Framework-Default ist.
> seen: [YYYY-MM-DD] optional pro Regel (nach P: einfügen) — Frische-Status (fresh/check/orphan) landet in registry.yaml, siehe _gotchas.md#legende.
