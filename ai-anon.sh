#!/usr/bin/env bash
# =============================================================================
# ai-anon.sh — Local Data Anonymizer (AI Context Pro) v2
#
# Ersetzt sensible Daten lokal BEVOR sie Claude erreichen.
# De-anonymisiert Claudes Antwort automatisch nach der Session.
#
# Usage:
#   ai-anon --protect "text"        # anonymisiert (Clipboard + stdout)
#   ai-anon --protect               # stdin-Modus
#   ai-anon --restore "text"        # de-anonymisiert + löscht Session-Map
#   ai-anon --restore               # stdin-Modus
#   ai-anon --detect "text"         # exit 0=placeholders, 1=raw-PII, 2=clean
#   ai-anon --show                  # zeigt Mapping-Tabelle
#   ai-anon --clear                 # löscht Session-Map
#   ai-anon --wrap                  # interaktiver Modus
#
# Mapping: ~/.ai-context/maps/session_YYYY-MM-DD.json
# Platzhalter: [P1] Person | [ORT_1] Ort | [TEL_1] Telefon | [MAIL_1] E-Mail
#              [B1] Betrag | [DAT_1] Datum | [UHR_1] Uhrzeit | [IBAN_1] IBAN
#              [FIRMA_1] Firma | [PROJ_1] Projekt
#
# Math-Detection: Bei Rechnungs-Keywords (schuldet, kostet, zahlt, Summe, ...)
#                 bleiben Zahlen/Beträge erhalten — nur Namen/Orte/Kontakte anon.
# =============================================================================
set -euo pipefail

GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; BOLD='\033[1m'; NC='\033[0m'

MAP_DIR="${HOME}/.ai-context/maps"
DATE_STAMP=$(date +%Y-%m-%d)
MAP_FILE="${MAP_DIR}/session_${DATE_STAMP}.json"
MODE="${1:-}"

mkdir -p "$MAP_DIR" 2>/dev/null || true

# ---- Initialisiere leere Map falls nicht vorhanden ----
init_map() {
  if [ ! -f "$MAP_FILE" ]; then
    python3 - "$MAP_FILE" "$DATE_STAMP" << 'PYEOF'
import json, sys, pathlib
pathlib.Path(sys.argv[1]).write_text(json.dumps({
    "version": 2,
    "date": sys.argv[2],
    "rechnung": False,
    "counters": {},
    "map": {}
}, ensure_ascii=False, indent=2), encoding='utf-8')
PYEOF
  fi
}

# ---- --clear ----
if [ "$MODE" = "--clear" ]; then
  rm -f "$MAP_DIR"/session_*.json 2>/dev/null || true
  # Legacy-Pfad räumen
  rm -f "${HOME}/.ai-context/.anon_map.json" 2>/dev/null || true
  echo -e "${GREEN}✅ Anonymisierungs-Mappings gelöscht.${NC}"
  exit 0
fi

# ---- --show ----
if [ "$MODE" = "--show" ]; then
  if [ ! -f "$MAP_FILE" ]; then
    echo -e "${YELLOW}Keine aktive Anonymisierungs-Session für heute.${NC}"
    exit 0
  fi
  echo -e "${CYAN}Session-Mapping ($DATE_STAMP):${NC}"
  python3 - "$MAP_FILE" << 'PYEOF'
import json, sys
data = json.loads(open(sys.argv[1]).read())
mapping = data.get("map", {})
print(f"  Modus: {'Rechnung (Zahlen bleiben)' if data.get('rechnung') else 'Standard (alles anon.)'}")
if not mapping:
    print("  (leer)")
    sys.exit(0)
for placeholder, real in sorted(mapping.items(), key=lambda x: (x[0].split('_')[0] if '_' in x[0] else x[0], x[0])):
    print(f"  {placeholder:<14} ← {real}")
PYEOF
  exit 0
fi

# ---- --detect: Prüft ob Prompt Placeholder enthält oder raw PII ----
if [ "$MODE" = "--detect" ]; then
  INPUT="${2:-}"
  [ -z "$INPUT" ] && INPUT=$(cat)
  python3 - "$INPUT" << 'PYEOF'
import re, sys
text = sys.argv[1]
# Placeholder-Pattern (aus ap: kommend)
if re.search(r'\[(?:P|ORT|TEL|MAIL|B|DAT|UHR|IBAN|FIRMA|PROJ)_?\d+\]', text):
    sys.exit(0)   # Placeholder: Option A greift → pass-through
# Raw PII erkannt?
patterns = [
    r'\b[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}\b',            # email
    r'\b[A-Z]{2}\d{2}(?:\s?\d{1,4}){4,9}\b',                            # IBAN
    r'(?:\+\d{1,3}[\s\-]?)?\(?\d{2,5}\)?[\s\-]?\d{3,5}[\s\-]?\d{3,5}',  # phone
    r'(?:[A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-\.]{1,25}\s){1,3}(?:GmbH|AG|UG|KG|OHG|GbR|e\.V\.|Inc\.?|Ltd\.?|LLC|Corp\.?|S\.A\.|BV|NV)\b',
    r'\b\d{5}\s+[A-ZÄÖÜ][A-Za-zÄÖÜäöüß\-]{2,}',                          # PLZ + Stadt
    r'(?i)\b(?:Herr|Frau|Hr\.|Fr\.|Dr\.|Prof\.)\s+[A-ZÄÖÜ][a-zäöüß\-]{2,}',  # Titel + Name
]
for p in patterns:
    if re.search(p, text):
        sys.exit(1)   # raw PII → Option B greift
sys.exit(2)   # clean
PYEOF
  exit $?
fi

# ---- --protect oder --restore ----
if [ "$MODE" = "--protect" ] || [ "$MODE" = "--restore" ]; then
  init_map
  INPUT="${2:-}"
  if [ -z "$INPUT" ]; then
    INPUT=$(cat)
  fi

  python3 - "$MAP_FILE" "$MODE" "$INPUT" << 'PYEOF'
import re, json, sys, pathlib

map_file = pathlib.Path(sys.argv[1])
mode     = sys.argv[2]
text     = sys.argv[3]

data = json.loads(map_file.read_text(encoding='utf-8'))
mapping  = data.get("map", {})
counters = data.get("counters", {})
reverse  = {v: k for k, v in mapping.items()}

# ─────────────────────────────────────────────────────────
# RESTORE — ersetzt Platzhalter durch echte Werte
# ─────────────────────────────────────────────────────────
if mode == "--restore":
    if not mapping:
        print(text)
        sys.exit(0)
    # Längste Platzhalter zuerst (verhindert Überlappung [P1] vs [P10])
    for ph, real in sorted(mapping.items(), key=lambda x: -len(x[0])):
        text = text.replace(ph, real)
    print("\033[0;32m🔓 AI Context: Echte Daten wiederhergestellt. Session-Map gelöscht.\033[0m", file=sys.stderr)
    print(text)
    # Session-Map löschen — sensible Zuordnungen nicht persistieren
    try:
        map_file.unlink()
    except FileNotFoundError:
        pass
    sys.exit(0)

# ─────────────────────────────────────────────────────────
# PROTECT — erkennt & ersetzt sensible Entitäten
# ─────────────────────────────────────────────────────────
changed = []

def next_placeholder(category):
    idx = counters.get(category, 0) + 1
    counters[category] = idx
    # Format: [P1], [ORT_1], [TEL_1] ...
    sep = "" if category in ("P", "B") else "_"
    return f"[{category}{sep}{idx}]"

def replace_or_reuse(real_value, category):
    real_value = real_value.strip()
    if real_value in reverse:
        return reverse[real_value]
    ph = next_placeholder(category)
    mapping[ph] = real_value
    reverse[real_value] = ph
    changed.append((real_value, ph))
    return ph

# ── Math-Detection: sollen Zahlen erhalten bleiben? ──
MATH_KEYWORDS = [
    r"\bschulde[tns]?\b", r"\bkostet?\b", r"\bzahlt?\b", r"\bbezahlt?\b", r"\bgesamt\b", r"\binsgesamt\b",
    r"\bsumme\b", r"\brechnung\b", r"\brechne\b", r"\bberechne\b", r"\bergibt\b", r"\bbetr[aä]gt\b",
    r"\bplus\b", r"\bminus\b", r"\bmal\b", r"\bgeteilt\b", r"\bist gleich\b",
    r"\bprozent\b", r"\bmehrwertsteuer\b", r"\bmwst\b", r"\bnetto\b", r"\bbrutto\b",
    r"\bpro\s+stunde\b", r"\bpro\s+tag\b", r"\bstundenlohn\b",
    r"\bwie\s*viel\b", r"\bwieviel\b",
]
is_math = any(re.search(kw, text, re.IGNORECASE) for kw in MATH_KEYWORDS)
data["rechnung"] = bool(data.get("rechnung")) or is_math

# ── 1. IBAN ──
text = re.sub(
    r'\b[A-Z]{2}\d{2}(?:\s?\d{1,4}){4,9}\b',
    lambda m: replace_or_reuse(m.group(0), "IBAN"),
    text
)

# ── 2. Email ──
text = re.sub(
    r'\b[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}\b',
    lambda m: replace_or_reuse(m.group(0), "MAIL"),
    text
)

# ── 3a. Telefon mit Marker (Tel/Handy/Mobil/Fon/Nr + ≥4 Ziffern) ──
def repl_tel_marked(m):
    marker = m.group(1)
    number = m.group(2).strip().rstrip('.,;:')
    ph = replace_or_reuse(number, "TEL")
    return f"{marker} {ph}"
text = re.sub(
    r'(?i)\b(Tel\.?|Telefon|Fon|Mobil|Mobile|Handy|Phone|Rufnummer|Nr\.?)[\s:\.]+(\+?[\d][\d\s\-\/]{3,25}\d)',
    repl_tel_marked,
    text
)

# ── 3b. Telefon ohne Marker (≥7 Ziffern, typische Formate) ──
text = re.sub(
    r'(?<![\w\.\d])(?:\+\d{1,3}[\s\-\/]?)?\(?\d{2,5}\)?[\s\-\/]?\d{3,5}[\s\-\/]?\d{2,5}(?:[\s\-]?\d{2,4})?(?![\w\.\d])',
    lambda m: replace_or_reuse(m.group(0).strip(), "TEL") if len(re.sub(r'\D', '', m.group(0))) >= 7 else m.group(0),
    text
)

# ── 4. Datum (DD.MM.YYYY | YYYY-MM-DD | DD/MM/YY) ──
text = re.sub(
    r'\b\d{1,2}\.\d{1,2}\.\d{2,4}\b|\b\d{4}-\d{2}-\d{2}\b|\b\d{1,2}/\d{1,2}/\d{2,4}\b',
    lambda m: replace_or_reuse(m.group(0), "DAT"),
    text
)

# ── 5. Uhrzeit ──
text = re.sub(
    r'\b\d{1,2}:\d{2}(?::\d{2})?(?:\s(?:Uhr|AM|PM|am|pm))?\b',
    lambda m: replace_or_reuse(m.group(0), "UHR"),
    text
)

# ── 6. PLZ + Stadt (deutsche Adresse) — case-insensitive ──
text = re.sub(
    r'(?i)\b\d{5}\s+[a-zäöü][a-zäöüß\-]{2,}(?:[\s\-][a-zäöü][a-zäöüß]+)*',
    lambda m: replace_or_reuse(m.group(0), "ORT"),
    text
)

# ── 7. Straßen-/Adressbezeichner (mit optionaler Hausnummer, Tippfehler-tolerant) ──
STREET_SUFFIX = r'(?:stra[ßs]e|strasse|str\.?|weg|all?ee?|platz|gasse|ring|damm|ufer|h[oö]fe|kehre|pfad|chaussee|zeile|steig|feld|berg|tal|hof|park|markt)'
text = re.sub(
    r'\b[A-ZÄÖÜ][a-zäöüß]{2,25}' + STREET_SUFFIX + r'(?:\s+\d{1,4}[a-zA-Z]?)?\b',
    lambda m: replace_or_reuse(m.group(0), "ORT"),
    text,
    flags=re.IGNORECASE
)

# ── 8. Geldbeträge (NUR wenn kein Math-Modus) — inkl. Wort-Währungen ──
if not is_math:
    # Suffix-Format: 50.000€ | 1.234,56 € | 100 CHF | 50£ | 5000 dollar
    text = re.sub(
        r'(?i)\b\d+(?:[.,]\d+)*\s?(?:€|£|\$|eur|euro|usd|dollar|chf|gbp|pfund|yen|jpy)(?!\w)',
        lambda m: replace_or_reuse(m.group(0).strip(), "B"),
        text
    )
    # Prefix-Format Wort-Währung: CHF 100 | EUR 1.234,56 | USD 500
    text = re.sub(
        r'(?i)\b(?:eur|euro|usd|dollar|chf|gbp|pfund|yen|jpy)\s?\d+(?:[.,]\d+)*(?!\w)',
        lambda m: replace_or_reuse(m.group(0).strip(), "B"),
        text
    )
    # Prefix-Format Symbol: €50 | $50 | £50
    text = re.sub(
        r'(?:€|\$|£)\s?\d+(?:[.,]\d{1,3})*(?:[.,]\d{2})?(?!\w)',
        lambda m: replace_or_reuse(m.group(0).strip(), "B"),
        text
    )

# ── 9. Firmen mit Rechtsform — case-insensitive ──
# FIRMA_CONTEXT_STOPWORDS: Wörter die VOR dem Firmennamen stehen können aber nicht dazugehören
# (z.B. "Miete Müller GmbH" → nur "Müller GmbH" ist die Firma)
FIRMA_CONTEXT_STOPWORDS = {
    "miete", "zahlung", "rechnung", "beratung", "kosten", "leistung",
    "projekt", "auftrag", "vertrag", "service", "support", "entwicklung",
    "wartung", "montage", "installation", "lieferung", "kauf", "verkauf",
    "an", "für", "fuer", "von", "bei", "mit", "durch", "nach", "zu",
}
def repl_firma(m):
    full = m.group(0).strip()
    words = full.split()
    # Führende Kontext-Wörter abstreifen, die nicht zum Firmennamen gehören
    while words and words[0].lower() in FIRMA_CONTEXT_STOPWORDS:
        words = words[1:]
    if not words:
        return full
    stripped = len(full.split()) - len(words)
    leading = " ".join(full.split()[:stripped])
    company = " ".join(words)
    return (leading + " " if leading else "") + replace_or_reuse(company, "FIRMA")

text = re.sub(
    # {2,25} statt {1,25}: mind. 3-Zeichen-Wörter (verhindert "an", "zu", "im" als Firmenteil)
    r'(?i)(?<!\w)(?:[a-zäöü][a-zäöüß\-\.]{2,25}\s){1,3}(?:gmbh|ag|ug|kg|ohg|gbr|e\.v\.|inc\.?|ltd\.?|llc|corp\.?|s\.a\.|bv|nv)(?:\s&\s(?:co\.?|kg|partner))?',
    repl_firma,
    text
)

# ── 10. Person mit Titel/Anrede (unterstützt gestapelte Titel: "Herr Dr. Weber") ──
text = re.sub(
    r'(?:(?:Herr|Frau|Hr\.|Fr\.|Dr\.|Prof\.|Dipl\.-?Ing\.?)\s+){1,3}(?:[A-ZÄÖÜ][a-zäöüß\-]{1,25}\s){0,2}[A-ZÄÖÜ][a-zäöüß\-]{1,25}',
    lambda m: replace_or_reuse(m.group(0), "P"),
    text
)

# ── 11. Namen-Marker: "Name: X" | "von X" | "an X" (nur explicit) ──
def repl_named(m):
    prefix = m.group(1)
    name = m.group(2).strip()
    ph = replace_or_reuse(name, "P")
    return f"{prefix} {ph}"
text = re.sub(
    r'(?i)\b(Name|Kunde|Auftraggeber|Mandant|Klient|Empf[aä]nger|Absender)[:.]?\s+([A-ZÄÖÜ][a-zäöüß\-]{2,20}(?:\s+[A-ZÄÖÜ][a-zäöüß\-]{2,25}){0,2})\b',
    repl_named,
    text
)

# ── 12. Vor- + Nachname (zwei Kapitalisierte Wörter) — konservativ ──
STOPWORDS = {
    # Artikel / Pronomen
    "Der", "Die", "Das", "Ein", "Eine", "Einen", "Einem", "Einer", "Eines", "Dem", "Den",
    "Ich", "Du", "Er", "Sie", "Es", "Wir", "Ihr", "Ihn", "Ihm", "Uns", "Euch",
    "Mein", "Dein", "Sein", "Ihr", "Unser", "Euer", "Kein", "Keine", "Keinen",
    "Dieser", "Diese", "Dieses", "Jener", "Jede", "Jeder", "Jedes", "Alle", "Alles",
    # Generische Nomen (oft großgeschrieben, keine Namen)
    "Rechnung", "Summe", "Betrag", "Geld", "Euro", "Cent", "Kosten", "Preis",
    "Zahlung", "Überweisung", "Ueberweisung", "Steuer", "Mehrwertsteuer", "Mwst",
    "Netto", "Brutto", "Rabatt", "Provision",
    "Morgen", "Mittag", "Abend", "Nacht", "Heute", "Gestern", "Uhr", "Zeit",
    "Stunde", "Stunden", "Minute", "Minuten", "Sekunde", "Sekunden",
    "Tag", "Tage", "Woche", "Wochen", "Monat", "Monate", "Jahr", "Jahre",
    "Std", "Min", "Sek",
    # Wochentage / Monate
    "Montag", "Dienstag", "Mittwoch", "Donnerstag", "Freitag", "Samstag", "Sonntag",
    "Januar", "Februar", "März", "April", "Mai", "Juni", "Juli", "August",
    "September", "Oktober", "November", "Dezember",
    # Begrüßung
    "Guten", "Hallo", "Hi", "Tschüss", "Danke", "Bitte", "Ja", "Nein", "Moin",
    "Prost", "Willkommen",
    # Richtungs-/Orts-Wörter (generisch)
    "Hier", "Dort", "Oben", "Unten", "Links", "Rechts", "Vorne", "Hinten",
    "Mitte", "Nähe", "Norden", "Süden", "Osten", "Westen",
    # Kommunikations-Begriffe
    "Tel", "Telefon", "Email", "Mail", "Phone", "Handy", "Mobil", "Mobile",
    "Fax", "Web", "URL", "Link", "Nr", "Nummer", "Hausnummer",
    "Adresse", "Straße", "Strasse", "Weg", "Platz", "Allee", "Ring",
    "Kunde", "Kunden", "Firma", "Name", "Namen", "Mandant", "Auftraggeber",
    "Empfänger", "Empfaenger", "Absender", "Herr", "Frau", "Familie",
    # Rechtsformen / Projekt-Keywords
    "GmbH", "AG", "Inc", "Ltd", "LLC", "UG", "KG", "OHG", "GbR", "Corp",
    "Projekt", "Project", "Auftrag", "Task", "Mandat", "Website", "Redesign",
    "Backend", "Frontend", "Migration", "Setup", "Deploy", "Release", "Feature",
    "Bug", "Fix", "Issue", "Sprint", "Ticket",
    # Dienstleistungs-/Tätigkeitsnomen (kein Personenname)
    "Beratung", "Beratungen", "Wartung", "Montage", "Installation", "Lieferung",
    "Service", "Support", "Entwicklung", "Leistung", "Leistungen",
    "Miete", "Mieten", "Zahlung", "Zahlungen", "Kauf", "Verkauf",
    "Vertrag", "Verträge", "Vertraege", "Abrechnung", "Buchung",
    "Angebot", "Angebote", "Anfrage", "Angebotsnummer", "Reparatur",
    "Planung", "Konzept", "Analyse", "Bericht", "Training", "Schulung",
    # Tech
    "JavaScript", "TypeScript", "Python", "Django", "React", "Next", "Node",
    "API", "HTTP", "HTTPS", "SQL", "CSS", "HTML", "JSON", "XML", "CSV", "PDF",
    "Git", "GitHub", "Docker",
    # Verben / Füllwörter (häufig am Satzanfang)
    "Und", "Oder", "Aber", "Dann", "Wenn", "Weil", "Also", "Dass", "Damit",
    "Doch", "Auch", "Nur", "Noch", "Schon", "Mal", "Sehr", "Bitte", "Gerne",
    "Wie", "Was", "Wo", "Wer", "Wann", "Warum", "Welche", "Welcher", "Welches",
    "Viel", "Wenig", "Mehr", "Weniger", "Alle", "Alles", "Ganz", "Ganze",
    # Sonstige
    "Gruß", "Gruss", "Gesamt", "Insgesamt", "Total", "Netto", "Brutto",
    "Ja", "Nein", "Ok", "OK",
}
def repl_fullname(m):
    first, last = m.group(1), m.group(2)
    if first in STOPWORDS or last in STOPWORDS:
        return m.group(0)
    full = f"{first} {last}"
    return replace_or_reuse(full, "P")
text = re.sub(
    r'(?<![\w\[])([A-ZÄÖÜ][a-zäöüß]{2,15})\s+([A-ZÄÖÜ][a-zäöüß]{2,20})(?![\w\]])',
    repl_fullname,
    text
)

# ── 13. Projekte ──
def repl_project(m):
    prefix = m.group(1)
    name = m.group(2).strip()
    ph = replace_or_reuse(name, "PROJ")
    return f"{prefix} {ph}"
text = re.sub(
    r'(?i)(Projekt(?:name)?|Project|Auftrag|Mandat)\s+([A-ZÄÖÜ][A-Za-zÄÖÜäöüß0-9\s\-]{2,40})',
    repl_project,
    text
)

# ── 14. Aggressive Einzelwort-Namen (nur in --protect: User hat explizit angefragt) ──
# Fängt Vornamen wie "Adi", "Max" in "X schuldet Y", "treffe ich X", "mit X" etc.
# Stopwords filtern Nomen & Füllwörter raus. Placeholder [P1] werden nicht getroffen
# (Kleinbuchstaben-Requirement nach Initial).
def repl_single_name(m):
    word = m.group(0)
    if word in STOPWORDS:
        return word
    # Nur wenn in Kontext eines Namens-Indikators (Verb/Präposition) ODER
    # wenn weitere PII bereits gefunden (changed ist nicht leer).
    return replace_or_reuse(word, "P")

NAME_CONTEXT = r'(?:schulde[tns]?|zahlt?|bezahlt?|kostet?|trifft?|treffe|treffen|ruft?|schreibt?|schreibe|kontaktiere|empfehlt?|empfiehlt|gibt?|gab|hat|heißt|heisst|meint|sagt|wohnt?|lebt?|kommt?)'
NAME_PREPS   = r'(?:mit|bei|von|an|für|fuer|zu|nach|zum|zur|gegen|über|ueber|auf|gegenüber|gegenueber)'

# Variante A: "X [Verb]" — Name vor Verb (Adi schuldet)
text = re.sub(
    r'(?<![\w\[])([A-ZÄÖÜ][a-zäöüß]{1,20})(?=\s+' + NAME_CONTEXT + r'\b)',
    lambda m: repl_single_name(m) if m.group(1) not in STOPWORDS else m.group(0),
    text
)

# Variante B: "[Verb/Präp] (optional Pronomen) X" — nach Verb/Präp
def repl_after_context(m):
    head   = m.group(1)   # "treffe ich " oder "mit "
    name   = m.group(2)
    if name in STOPWORDS:
        return m.group(0)
    ph = replace_or_reuse(name, "P")
    return head + ph
text = re.sub(
    r'\b(' + NAME_CONTEXT + r'|' + NAME_PREPS + r')\s+((?:ich|mich|mir|dir|dem|der|den|das)\s+)?([A-ZÄÖÜ][a-zäöüß]{1,20})(?![\w\]])',
    lambda m: (
        m.group(0) if m.group(3) in STOPWORDS else
        f"{m.group(1)} {m.group(2) or ''}{replace_or_reuse(m.group(3), 'P')}"
    ),
    text
)

# Variante C: Einzelwort nach Komma-Liste (z.B. "morgen treffe ich Adi, Tel 12345, Sonnenallee")
# Nur wenn bereits PII erkannt wurde (sonst zu aggressiv).
if changed:
    text = re.sub(
        r'(?<![\w\[])([A-ZÄÖÜ][a-zäöüß]{2,20})(?![\w\]])',
        lambda m: replace_or_reuse(m.group(1), "P") if m.group(1) not in STOPWORDS else m.group(0),
        text
    )

# ── Persist ──
data["map"]      = mapping
data["counters"] = counters
map_file.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding='utf-8')

# ── Output ──
if changed:
    mode_label = "Rechnung (Zahlen bleiben)" if is_math else "Standard"
    print(f"\033[0;32m🔒 AI Context: Daten lokal geschützt [{mode_label}]\033[0m", file=sys.stderr)
    for real, ph in changed:
        shortened = real if len(real) <= 40 else real[:37] + "..."
        print(f"\033[0;32m   {shortened} → {ph}\033[0m", file=sys.stderr)

print(text)
PYEOF
  exit 0
fi

# ---- --wrap: Interaktiver Modus ----
if [ "$MODE" = "--wrap" ]; then
  init_map
  echo -e "${BOLD}🔒 AI Context Anonymisierungs-Modus${NC}"
  echo -e "${CYAN}   Eingabe → anonymisiert → Clipboard${NC}"
  echo -e "${YELLOW}   Beenden: Ctrl+C | Map löschen: ai-anon --clear${NC}"
  echo ""

  while true; do
    printf "${GREEN}> ${NC}"
    IFS= read -r INPUT || break
    [ -z "$INPUT" ] && continue

    ANON_TEXT=$(printf '%s' "$INPUT" | bash "$0" --protect 2>/dev/null)

    if command -v pbcopy &>/dev/null; then
      printf '%s' "$ANON_TEXT" | pbcopy
      echo -e "${CYAN}   → Zwischenablage (Cmd+V in Claude einfügen)${NC}"
    elif command -v xclip &>/dev/null; then
      printf '%s' "$ANON_TEXT" | xclip -selection clipboard
      echo -e "${CYAN}   → Zwischenablage (Ctrl+V in Claude einfügen)${NC}"
    fi
    echo -e "${GREEN}   $ANON_TEXT${NC}"
    echo ""
  done
  exit 0
fi

# ---- Hilfe ----
echo -e "${BOLD}AI Context — Lokaler Datenschutz (v2)${NC}"
echo ""
echo -e "${CYAN}Shortcut-Usage (nach install):${NC}"
echo -e "  ${GREEN}ap: Max Müller zahlt 50€ an Firma XY GmbH${NC}     # anonymisiert + Clipboard"
echo -e "  ${GREEN}ar${NC}                                             # de-anonymisiert Clipboard"
echo ""
echo -e "${CYAN}Direct:${NC}"
echo -e "  ai-anon --protect \"text\"        # anonymisiert"
echo -e "  ai-anon --restore \"text\"        # de-anonymisiert + löscht Session"
echo -e "  ai-anon --detect \"text\"         # 0=placeholders, 1=raw PII, 2=clean"
echo -e "  ai-anon --wrap                    # interaktiver Modus"
echo -e "  ai-anon --show                    # Mapping-Tabelle"
echo -e "  ai-anon --clear                   # Session-Maps löschen"
echo ""
echo -e "${GREEN}Platzhalter:${NC}"
echo -e "  [P1] Person  [ORT_1] Ort  [TEL_1] Telefon  [MAIL_1] E-Mail"
echo -e "  [B1] Betrag  [DAT_1] Datum  [UHR_1] Uhrzeit  [IBAN_1] IBAN"
echo -e "  [FIRMA_1] Firma  [PROJ_1] Projekt"
echo ""
echo -e "${GREEN}Rechnungs-Modus (auto):${NC}"
echo -e "  Bei Keywords wie 'schuldet/kostet/zahlt/Summe/Rechnung' bleiben"
echo -e "  Zahlen & Beträge erhalten — nur Namen/Orte/Kontakte werden anon."
