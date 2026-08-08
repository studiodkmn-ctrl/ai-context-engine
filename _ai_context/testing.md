# 🧪 Testing — ai-context-engine
> **Test strategy for the engine itself (not a per-project template).**
> Load for: writing tests, CI failures, verifying a fix actually does something.
> Last updated: 2026-08-06

---

## Drei Prüfschichten (`.github/workflows/ci.yml`)
```
1. shellcheck        Alle *.sh, --severity=warning.
2. MCP smoke test     npm ci && build in mcp/, dann node test/smoke.mjs
                      — echter stdio-Client gegen alle 5 Tools.
3. ai-verify-self.sh  E2E: Dummy-Next.js-Projekt, Setup, prüft ob locate()
                      einen Button findet + eine API-Änderung
                      backend/endpoints.md wirklich invalidiert.
                      Prüft WIRKUNG, nicht nur Durchlauf.
```

## Lokal ausführen
```bash
find . -name "*.sh" -not -path "./mcp/node_modules/*" -not -path "./.git/*" \
  -print0 | xargs -0 shellcheck --severity=warning
cd mcp && npm ci && npm run build && node test/smoke.mjs
bash _ai_context_template/scripts/ai-verify-self.sh   # KEEP_SANDBOX=1 zum Debuggen
```

---

## Regel
```
✗ "Skript läuft ohne Fehler durch"    — reicht nicht (⇒ _gotchas.md#silent_noop_needs_effect_test)
✓ "Skript hat die behauptete Wirkung" — Datei/Seiteneffekt wirklich geprüft
```

---
> WRITEBACK RULE: Neue Prüfschicht in ci.yml → hier ergänzen.
