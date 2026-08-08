---
name: ai-fix
description: >-
  Findet die Ursache von UI-Bugs schnell statt die Codebase zu durchsuchen.
  Nutzen wenn ein interaktives Element nicht funktioniert — Button reagiert
  nicht, Link/Navigation tot, Formular sendet nicht ab, Klick ohne Wirkung,
  falscher State nach Aktion. Routet das Symptom über die Interaction Map
  und bekannte Debug-Patterns direkt zur verdächtigen Datei.
---

# ai-fix — Symptom-Router für UI-Bugs

Ziel: Vom Bug-Bericht zur Ursache in **einem Schritt**, ohne die Codebase
blind zu durchsuchen. Die Interaction Map und `debug_patterns.md` kennen den
Weg bereits — Element → Datei:Zeile → Handler → State → Endpoint.

## Wann dieses Skill greift

Der Nutzer meldet einen Bug an einem interaktiven Element:
Button, Link, Navigation, Formular, Klick/Submit ohne Wirkung, falscher
State oder fehlender API-Call nach einer Aktion.

Nicht-UI-Bugs (Build-Fehler, reine Backend-Logik, Typfehler) → normal
vorgehen, dieses Skill bringt dort keinen Vorteil.

## Workflow

### Schritt 1 — Symptom routen
Führe aus (Bug-Beschreibung des Nutzers wörtlich übergeben):

```
bash _ai_context/scripts/ai-symptom-router.sh "<bug beschreibung>"
```

Der Router liefert:
- **INTERACTION MAP** — passende UI-Elemente mit Datei:Zeile, Handler, Store, Endpoint
- **DEBUG PATTERNS** — bekannte Symptome; bei starkem Treffer einen `TOP-FIX`-Block
- **GOTCHAS** — bekannte Fallen
- **EMPFOHLEN ZU LESEN** — die exakten Dateien
- Marker `__ROUTER__:<datei1>|<datei2>` (maschinenlesbar)

### Schritt 2 — Wenn TOP-FIX vorhanden
Zeigt der Router einen `TOP-FIX`-Block, ist der Bug bekannt. Antworte zuerst:
`Bekannter Fehler (P{N}): {ID}` — dann wende den Fix aus dem Block an.
Springe zu Schritt 5.

### Schritt 3 — Verdächtige lesen
Lies **nur** die unter `EMPFOHLEN ZU LESEN` genannten Dateien — nicht mehr.
Findet der Router kein Element, lies `_ai_context/_interaction_map.md` und
suche das betroffene Element manuell.

### Schritt 4 — Trace-Kette prüfen
Gehe die Kette des verdächtigen Elements Glied für Glied durch und finde
das erste defekte:

1. **Element** — ist der Handler überhaupt verdrahtet? (`onClick`/`onSubmit` gesetzt?)
2. **Handler** — wirft er früh raus, fehlt `await`, falsche Bedingung, `preventDefault`?
3. **State/Store** — wird der Store korrekt gelesen/geschrieben? Stimmt der Selector?
4. **Endpoint** — richtige URL/Methode? Fehlerbehandlung? Antwort verarbeitet?

Nenne explizit, welches Glied bricht und warum.

### Schritt 5 — Minimalen Fix anwenden
Behebe **nur** die gefundene Ursache. Kein Umbau, keine Zusatz-Refactorings.
Wende Projektregeln aus den Quick Facts automatisch an.

### Schritt 6 — Verify-Loop
Nach dem Fix ausführen:

```
bash _ai_context/scripts/ai-verify.sh
```

Reagiere auf die `RESULT:`-Zeile:

- **PASS** → weiter zu Schritt 7.
- **FAIL** → lies die ausgegebenen Fehler, behebe sie, führe `ai-verify.sh`
  erneut aus. **Maximal 3 Runden.** Ist es nach 3 Runden nicht sauber,
  stoppe und melde dem Nutzer den verbleibenden Fehler — rate nicht weiter
  und baue nichts um, was nichts mit dem Bug zu tun hat.
- **TIMEOUT** → melde es dem Nutzer; nicht blind wiederholen.
- **NO-COMMAND** → kein Verifier vorhanden. Weise den Nutzer darauf hin, dass
  der Fix ungeprüft ist, und schlage vor:
  `bash _ai_context/scripts/ai-verify.sh --set "npm run <script>"`.

### Schritt 7 — Lern-Loop schließen
Nur bei **PASS** und nur wenn der Bug verallgemeinerbar ist (kein reiner
Tippfehler): trage ihn in `debug_patterns.md` ein, damit der Router ihn beim
nächsten Mal sofort findet.

1. Dedup-Check zuerst:
   `bash _ai_context/check_context_hash.sh --dedup _ai_context/debug_patterns.md`
2. `DUPLICATE:<id>` → bestehenden Eintrag aktualisieren statt neu anlegen.
3. `NEW` → neuen Eintrag im Code-Format anhängen:
   ```
   ID: <kurz_sprechend>
   P: 2
   → <was war kaputt>
   ? <Symptom — wie der Nutzer es gemeldet hat>
   fix: <Lösung als Code>
   @ <betroffene Datei(en)>
   ```
   Das `? Symptom`-Feld ist entscheidend — danach matcht der Router.

### Schritt 8 — Impact-Graph füttern
Hat der Fix **mehrere Dateien** berührt, lerne die Beziehung:

```
bash _ai_context/scripts/ai-impact-learn.sh <bug-datei> <weitere-editierte-datei...>
```

`<bug-datei>` = wo die Ursache lag, danach alle weiteren Dateien, die du im
selben Fix geändert hast. Beim nächsten Bug in derselben Datei zeigt der
Symptom-Router diese als „häufig mit-betroffen". Ein-Datei-Fix → Schritt entfällt.

Antworte dem Nutzer zum Schluss kurz: welches Glied der Kette gebrochen war,
was der Fix war, Verify-Ergebnis.
