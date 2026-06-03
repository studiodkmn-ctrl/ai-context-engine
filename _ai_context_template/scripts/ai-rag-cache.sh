#!/usr/bin/env bash
# =============================================================================
# ai-rag-cache.sh — SQLite RAG-Cache + Ollama-Embeddings (v6.0 Sprint 2)
#
# Speichert Chunk-Embeddings + Query-Ergebnisse in SQLite.
# Kein Cloud-Zugriff — alles lokal via Ollama.
#
# Usage:
#   bash ai-rag-cache.sh --init                         # DB-Schema anlegen
#   bash ai-rag-cache.sh --embed-chunks [registry.yaml] # Alle Chunks einbetten
#   bash ai-rag-cache.sh --find <query> [registry.yaml] # Semantische Suche
#   bash ai-rag-cache.sh --lookup <query>               # Nur Cache prüfen (kein Ollama)
#   bash ai-rag-cache.sh --invalidate <chunk_hash>      # Veraltete Cache-Einträge löschen
#   bash ai-rag-cache.sh --stats                        # Cache-Statistiken
#   bash ai-rag-cache.sh --clear-cache                  # Query-Cache leeren (Embeddings behalten)
#   bash ai-rag-cache.sh --clear-all                    # Alles löschen (inkl. Embeddings)
# =============================================================================
set -euo pipefail

# ---- Pro-Edition-Guard ----
if [ "$(cat "$HOME/.ai-context/edition" 2>/dev/null)" != "pro" ]; then
  echo "❌ ai-rag-cache.sh ist AI Context Pro." >&2
  echo "   Upgrade: bash ~/.ai-context/install.sh --pro" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTEXT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REGISTRY="${CONTEXT_DIR}/registry.yaml"

# Globale RAG-DB (über Projekte geteilt)
RAG_DB="${HOME}/.ai-context/rag.db"

# Ollama-Konfiguration
OLLAMA_CONF="${HOME}/.ai-context/ollama.conf"
OLLAMA_URL="http://localhost:11434"
OLLAMA_EMBED_MODEL="nomic-embed-text"   # Kleines Embedding-Modell (~274MB)

# Modell aus Config laden falls vorhanden
if [ -f "$OLLAMA_CONF" ]; then
  # shellcheck source=/dev/null
  source "$OLLAMA_CONF" 2>/dev/null || true
fi

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; RED='\033[0;31m'; NC='\033[0m'

# ---- Ollama-Status prüfen ----
is_ollama_running() {
  curl -s --max-time 2 "${OLLAMA_URL}/api/tags" > /dev/null 2>&1
}

# ---- DB-Pfad sicherstellen ----
ensure_db_dir() {
  mkdir -p "$(dirname "$RAG_DB")"
}

# ===========================================================================
# --init: DB-Schema anlegen
# ===========================================================================
if [ "${1:-}" = "--init" ]; then
  ensure_db_dir
  python3 - "$RAG_DB" << 'PYEOF'
import sqlite3, sys
db = sqlite3.connect(sys.argv[1])
db.executescript("""
CREATE TABLE IF NOT EXISTS chunk_embeddings (
    chunk_id    TEXT NOT NULL,
    chunk_hash  TEXT NOT NULL,
    embedding   TEXT NOT NULL,
    model       TEXT NOT NULL,
    created_at  INTEGER DEFAULT (strftime('%s','now')),
    PRIMARY KEY (chunk_id, model)
);

CREATE TABLE IF NOT EXISTS query_cache (
    query_hash   TEXT NOT NULL,
    query_text   TEXT NOT NULL,
    chunk_ids    TEXT NOT NULL,
    chunk_hashes TEXT NOT NULL,
    model        TEXT NOT NULL,
    hits         INTEGER DEFAULT 0,
    created_at   INTEGER DEFAULT (strftime('%s','now')),
    PRIMARY KEY  (query_hash, model)
);

CREATE INDEX IF NOT EXISTS idx_chunk_hash ON chunk_embeddings(chunk_hash);
CREATE INDEX IF NOT EXISTS idx_cache_created ON query_cache(created_at);
""")
db.commit()
db.close()
print("OK")
PYEOF
  echo -e "${GREEN}✅ RAG-DB initialisiert:${NC} $RAG_DB"
  exit 0
fi

# ===========================================================================
# --embed-chunks [registry.yaml]: Alle Chunk-Embeddings via Ollama generieren
# ===========================================================================
if [ "${1:-}" = "--embed-chunks" ]; then
  REGISTRY_PATH="${2:-$REGISTRY}"
  [ ! -f "$REGISTRY_PATH" ] && \
    echo -e "${RED}❌ registry.yaml nicht gefunden:${NC} $REGISTRY_PATH" && exit 1

  ensure_db_dir

  if ! is_ollama_running; then
    echo -e "${RED}❌ Ollama läuft nicht.${NC}"
    echo "   Starten: ollama serve"
    exit 1
  fi

  # Prüfe ob Embedding-Modell verfügbar
  if ! curl -s "${OLLAMA_URL}/api/tags" | grep -q "$OLLAMA_EMBED_MODEL"; then
    echo -e "${YELLOW}📦 Lade Embedding-Modell: $OLLAMA_EMBED_MODEL (~274MB)...${NC}"
    ollama pull "$OLLAMA_EMBED_MODEL" || {
      echo -e "${RED}❌ Modell konnte nicht geladen werden.${NC}"
      exit 1
    }
  fi

  # DB initialisieren
  bash "$0" --init > /dev/null 2>&1

  echo -e "${CYAN}🧮 Generiere Chunk-Embeddings (Ollama: $OLLAMA_EMBED_MODEL)...${NC}"

  python3 - "$REGISTRY_PATH" "$RAG_DB" "$OLLAMA_URL" "$OLLAMA_EMBED_MODEL" "$CONTEXT_DIR" << 'PYEOF'
import sys, re, pathlib, sqlite3, json, urllib.request, urllib.error, hashlib

registry_path = sys.argv[1]
db_path = sys.argv[2]
ollama_url = sys.argv[3]
embed_model = sys.argv[4]
context_dir = pathlib.Path(sys.argv[5])

ANCHOR_RE = re.compile(
    r'<!-- #(\w+) -->\n([\s\S]*?)<!-- /\1 -->',
    re.MULTILINE
)

# Registry parsen
chunks = []
current = {}
with open(registry_path, encoding='utf-8') as f:
    for line in f:
        s = line.strip()
        if s.startswith('- id:'):
            if current.get('id'):
                chunks.append(current)
            current = {'id': s.split(':',1)[1].strip(), 'file':'', 'hash':''}
        elif s.startswith('file:') and current:
            current['file'] = s.split(':',1)[1].strip()
        elif s.startswith('hash:') and current:
            current['hash'] = s.split(':',1)[1].strip().strip('"')
    if current.get('id'):
        chunks.append(current)

db = sqlite3.connect(db_path)

def get_embedding(text, model, url):
    """Ollama Embedding API aufrufen."""
    payload = json.dumps({'model': model, 'prompt': text}).encode('utf-8')
    req = urllib.request.Request(
        f'{url}/api/embeddings',
        data=payload,
        headers={'Content-Type': 'application/json'},
        method='POST'
    )
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.loads(resp.read())['embedding']

def extract_chunk(chunk_id, file_rel):
    fpath = context_dir / file_rel
    if not fpath.exists():
        return None
    content = fpath.read_text(encoding='utf-8')
    m = ANCHOR_RE.search(content.replace(f'<!-- #{chunk_id} -->', f'<!-- #{chunk_id} -->'))
    # Direkter Anker-Match
    pattern = re.compile(
        r'<!-- #' + re.escape(chunk_id) + r' -->\n([\s\S]*?)<!-- /' + re.escape(chunk_id) + r' -->',
        re.MULTILINE
    )
    m2 = pattern.search(content)
    if m2:
        return m2.group(1).strip()
    return None

skipped = 0
embedded = 0
errors = 0

for c in chunks:
    chunk_id = c['id']
    chunk_hash = c.get('hash', '')
    file_rel = c.get('file', '')

    # Prüfe ob bereits aktuelles Embedding vorhanden
    row = db.execute(
        'SELECT chunk_hash FROM chunk_embeddings WHERE chunk_id=? AND model=?',
        (chunk_id, embed_model)
    ).fetchone()

    if row and row[0] == chunk_hash:
        print(f"  ⏭️  {chunk_id} (aktuell)")
        skipped += 1
        continue

    # Chunk-Text extrahieren
    chunk_text = extract_chunk(chunk_id, file_rel)
    if not chunk_text:
        print(f"  ⚠️  {chunk_id} (Chunk-Text nicht gefunden)")
        errors += 1
        continue

    # Embedding generieren
    try:
        embedding = get_embedding(chunk_text, embed_model, ollama_url)
        embedding_str = ','.join(str(v) for v in embedding)

        db.execute(
            '''INSERT OR REPLACE INTO chunk_embeddings
               (chunk_id, chunk_hash, embedding, model)
               VALUES (?, ?, ?, ?)''',
            (chunk_id, chunk_hash, embedding_str, embed_model)
        )
        db.commit()
        print(f"  ✅ {chunk_id} ({len(embedding)}d)")
        embedded += 1
    except Exception as e:
        print(f"  ❌ {chunk_id}: {e}")
        errors += 1

db.close()
print(f"\nErgebnis: {embedded} eingebettet | {skipped} aktuell | {errors} Fehler")
PYEOF
  exit 0
fi

# ===========================================================================
# --find <query> [registry.yaml]: Semantische Suche (Ollama + Cache)
# Fallback: Keyword-Suche wenn Ollama nicht läuft
# ===========================================================================
if [ "${1:-}" = "--find" ]; then
  shift
  QUERY="${1:-}"
  REGISTRY_PATH="${2:-$REGISTRY}"
  [ -z "$QUERY" ] && echo "Usage: --find <query> [registry.yaml]" && exit 1
  [ ! -f "$REGISTRY_PATH" ] && \
    echo -e "${RED}❌ registry.yaml nicht gefunden.${NC}" && exit 1

  python3 - "$QUERY" "$REGISTRY_PATH" "$RAG_DB" "$OLLAMA_URL" "$OLLAMA_EMBED_MODEL" << 'PYEOF'
import sys, re, math, sqlite3, json, urllib.request, hashlib, pathlib

query = sys.argv[1]
registry_path = sys.argv[2]
db_path = sys.argv[3]
ollama_url = sys.argv[4]
embed_model = sys.argv[5]

# Registry parsen
chunks = []
current = {}
with open(registry_path, encoding='utf-8') as f:
    for line in f:
        s = line.strip()
        if s.startswith('- id:'):
            if current.get('id'):
                chunks.append(current)
            current = {'id': s.split(':',1)[1].strip(), 'tags':[], 'priority':2,
                       'type':'', 'file':'', 'tokens':0, 'hash':''}
        elif s.startswith('type:') and current:
            current['type'] = s.split(':',1)[1].strip()
        elif s.startswith('priority:') and current:
            try: current['priority'] = int(s.split(':',1)[1].strip())
            except: pass
        elif s.startswith('file:') and current:
            current['file'] = s.split(':',1)[1].strip()
        elif s.startswith('tags:') and current:
            tags_raw = s.split(':',1)[1].strip().strip('[]')
            current['tags'] = [t.strip() for t in tags_raw.split(',') if t.strip()]
        elif s.startswith('tokens:') and current:
            try: current['tokens'] = int(s.split(':',1)[1].strip())
            except: pass
        elif s.startswith('hash:') and current:
            current['hash'] = s.split(':',1)[1].strip().strip('"')
    if current.get('id'):
        chunks.append(current)

def keyword_fallback(query, chunks):
    """Sprint 1 Fallback: Keyword-Suche."""
    q_words = set(re.findall(r'[a-z][a-z0-9_-]+', query.lower()))
    results = []
    for c in chunks:
        haystack = set([c['id']] + c['tags'] + [c['type']])
        haystack.update(re.split(r'[_\-]', c['id']))
        score = len(q_words & haystack)
        if score > 0:
            results.append((c['priority'], -score, c['id'], c['file'], c['tokens']))
    results.sort()
    return results

def cosine_sim(a, b):
    dot = sum(x*y for x, y in zip(a, b))
    mag_a = math.sqrt(sum(x*x for x in a))
    mag_b = math.sqrt(sum(x*x for x in b))
    if mag_a * mag_b == 0:
        return 0.0
    return dot / (mag_a * mag_b)

def is_ollama_running():
    try:
        req = urllib.request.Request(f'{ollama_url}/api/tags', method='GET')
        urllib.request.urlopen(req, timeout=2)
        return True
    except:
        return False

def get_embedding(text, model, url):
    payload = json.dumps({'model': model, 'prompt': text}).encode('utf-8')
    req = urllib.request.Request(
        f'{url}/api/embeddings',
        data=payload,
        headers={'Content-Type': 'application/json'},
        method='POST'
    )
    with urllib.request.urlopen(req, timeout=15) as resp:
        return json.loads(resp.read())['embedding']

# ---- Query-Cache prüfen ----
query_hash = hashlib.sha1(f'{query}:{embed_model}'.encode()).hexdigest()[:12]
db_available = pathlib.Path(db_path).exists()

if db_available:
    try:
        db = sqlite3.connect(db_path)

        # Cache-Lookup
        row = db.execute(
            'SELECT chunk_ids, chunk_hashes FROM query_cache WHERE query_hash=? AND model=?',
            (query_hash, embed_model)
        ).fetchone()

        if row:
            chunk_ids = json.loads(row[0])
            chunk_hashes = json.loads(row[1])

            # Validiere dass alle Chunk-Hashes noch aktuell sind
            current_hashes = {c['id']: c['hash'] for c in chunks}
            still_valid = all(
                current_hashes.get(cid, '') == chunk_hashes.get(cid, 'MISSING')
                for cid in chunk_ids
            )

            if still_valid:
                db.execute(
                    'UPDATE query_cache SET hits=hits+1 WHERE query_hash=? AND model=?',
                    (query_hash, embed_model)
                )
                db.commit()
                db.close()

                # Cache-Hit: Ergebnis ausgeben
                result_chunks = {c['id']: c for c in chunks}
                print(f"\n  [CACHE-HIT] {'P':<3} {'ID':<32} {'Datei':<30} {'~Tok':>5}")
                print(f"  {'-'*3} {'-'*32} {'-'*30} {'-'*5}")
                for cid in chunk_ids:
                    c = result_chunks.get(cid)
                    if c:
                        print(f"  P{c['priority']}  {c['id']:<32} {c['file']:<30} {c['tokens']:>4}")
                sys.exit(0)

        db.close()
    except Exception:
        pass

# ---- Ollama Semantische Suche ----
if is_ollama_running() and db_available:
    try:
        db = sqlite3.connect(db_path)

        # Query-Embedding generieren
        query_embedding = get_embedding(query, embed_model, ollama_url)

        # Alle Chunk-Embeddings laden
        rows = db.execute(
            'SELECT chunk_id, chunk_hash, embedding FROM chunk_embeddings WHERE model=?',
            (embed_model,)
        ).fetchall()

        if rows:
            chunk_id_map = {c['id']: c for c in chunks}
            current_hashes = {c['id']: c['hash'] for c in chunks}

            scores = []
            for chunk_id, stored_hash, embedding_str in rows:
                # Nur aktuelle Embeddings verwenden
                if current_hashes.get(chunk_id, '') != stored_hash:
                    continue
                c = chunk_id_map.get(chunk_id)
                if not c:
                    continue
                emb = [float(v) for v in embedding_str.split(',')]
                sim = cosine_sim(query_embedding, emb)
                scores.append((sim, c))

            scores.sort(reverse=True)

            if scores:
                # Top-8 Ergebnisse
                results = [(c['priority'], -sim, c['id'], c['file'], c['tokens'])
                           for sim, c in scores[:8] if sim > 0.3]
                results.sort()

                # In Cache speichern
                top_ids = [c['id'] for _, c in scores[:5] if _ > 0.3]
                top_hashes = {cid: current_hashes.get(cid, '') for cid in top_ids}
                db.execute(
                    '''INSERT OR REPLACE INTO query_cache
                       (query_hash, query_text, chunk_ids, chunk_hashes, model)
                       VALUES (?, ?, ?, ?, ?)''',
                    (query_hash, query[:200], json.dumps(top_ids),
                     json.dumps(top_hashes), embed_model)
                )
                db.commit()
                db.close()

                print(f"\n  [OLLAMA] {'P':<3} {'ID':<32} {'Datei':<30} {'~Tok':>5}")
                print(f"  {'-'*3} {'-'*32} {'-'*30} {'-'*5}")
                for prio, neg_sim, cid, f, tok in results:
                    sim_pct = int(-neg_sim * 100)
                    print(f"  P{prio}  {cid:<32} {f:<30} {tok:>4}  (sim:{sim_pct}%)")
                sys.exit(0)

        db.close()
    except Exception as e:
        # Ollama-Fehler → Keyword-Fallback
        pass

# ---- Keyword-Fallback (Sprint 1) ----
results = keyword_fallback(query, chunks)
if not results:
    print("  (keine Treffer)")
    sys.exit(0)

src = "[KEYWORD]" if not (db_available and is_ollama_running()) else "[KEYWORD-FALLBACK]"
print(f"\n  {src} {'P':<3} {'ID':<32} {'Datei':<30} {'~Tok':>5}")
print(f"  {'-'*3} {'-'*32} {'-'*30} {'-'*5}")
for prio, neg_score, cid, f, tok in results:
    score = -neg_score
    print(f"  P{prio}  {cid:<32} {f:<30} {tok:>4}  (score:{score})")
PYEOF
  exit 0
fi

# ===========================================================================
# --lookup <query>: Nur Cache prüfen — kein Ollama-Call
# ===========================================================================
if [ "${1:-}" = "--lookup" ]; then
  QUERY="${2:-}"
  [ -z "$QUERY" ] && echo "Usage: --lookup <query>" && exit 1
  [ ! -f "$RAG_DB" ] && echo "MISS" && exit 0

  python3 - "$QUERY" "$RAG_DB" "$OLLAMA_EMBED_MODEL" << 'PYEOF'
import sys, hashlib, sqlite3, json

query = sys.argv[1]
db_path = sys.argv[2]
model = sys.argv[3]
query_hash = hashlib.sha1(f'{query}:{model}'.encode()).hexdigest()[:12]

try:
    db = sqlite3.connect(db_path)
    row = db.execute(
        'SELECT chunk_ids FROM query_cache WHERE query_hash=? AND model=?',
        (query_hash, model)
    ).fetchone()
    db.close()
    if row:
        ids = json.loads(row[0])
        print('HIT:' + ','.join(ids))
    else:
        print('MISS')
except:
    print('MISS')
PYEOF
  exit 0
fi

# ===========================================================================
# --invalidate <chunk_hash>: Veraltete Cache-Einträge löschen
# ===========================================================================
if [ "${1:-}" = "--invalidate" ]; then
  CHUNK_HASH="${2:-}"
  [ -z "$CHUNK_HASH" ] && echo "Usage: --invalidate <chunk_hash>" && exit 1
  [ ! -f "$RAG_DB" ] && exit 0

  python3 - "$RAG_DB" "$CHUNK_HASH" << 'PYEOF'
import sys, sqlite3, json

db = sqlite3.connect(sys.argv[1])
target_hash = sys.argv[2]

# Lösche query_cache Einträge die diesen chunk_hash referenzieren
rows = db.execute('SELECT query_hash, chunk_hashes FROM query_cache').fetchall()
deleted = 0
for qhash, hashes_json in rows:
    hashes = json.loads(hashes_json)
    if target_hash in hashes.values():
        db.execute('DELETE FROM query_cache WHERE query_hash=?', (qhash,))
        deleted += 1

# Lösche chunk_embedding für diesen hash
db.execute('DELETE FROM chunk_embeddings WHERE chunk_hash=?', (target_hash,))
db.commit()
db.close()
if deleted > 0:
    print(f"  Cache: {deleted} Einträge invalidiert (hash: {target_hash[:12]})")
PYEOF
  exit 0
fi

# ===========================================================================
# --stats: Cache-Statistiken
# ===========================================================================
if [ "${1:-}" = "--stats" ]; then
  [ ! -f "$RAG_DB" ] && echo "RAG-DB nicht vorhanden. Bitte --init ausführen." && exit 0

  python3 - "$RAG_DB" "$OLLAMA_EMBED_MODEL" << 'PYEOF'
import sys, sqlite3

db = sqlite3.connect(sys.argv[1])
model = sys.argv[2]

emb_count = db.execute('SELECT COUNT(*) FROM chunk_embeddings WHERE model=?', (model,)).fetchone()[0]
emb_models = [r[0] for r in db.execute('SELECT DISTINCT model FROM chunk_embeddings').fetchall()]
cache_count = db.execute('SELECT COUNT(*) FROM query_cache WHERE model=?', (model,)).fetchone()[0]
total_hits = db.execute('SELECT SUM(hits) FROM query_cache WHERE model=?', (model,)).fetchone()[0] or 0
top_queries = db.execute(
    'SELECT query_text, hits FROM query_cache WHERE model=? ORDER BY hits DESC LIMIT 5',
    (model,)
).fetchall()
db.close()

hit_rate = int(total_hits / cache_count * 100) if cache_count > 0 else 0

print(f"\n  RAG-DB: {sys.argv[1]}")
print(f"  {'─'*55}")
print(f"  Embedding-Modell: {model}")
print(f"  Chunk-Embeddings: {emb_count} gespeichert")
print(f"  Verfügbare Modelle: {', '.join(emb_models) if emb_models else 'keine'}")
print(f"  {'─'*55}")
print(f"  Query-Cache:  {cache_count} Einträge | {total_hits} Gesamttreffer | {hit_rate}% Hit-Rate")
if top_queries:
    print(f"  Top Queries:")
    for q, h in top_queries:
        print(f"    ({h}x) {q[:50]}")
print()
PYEOF
  exit 0
fi

# ===========================================================================
# --clear-cache: Query-Cache leeren (Embeddings bleiben)
# ===========================================================================
if [ "${1:-}" = "--clear-cache" ]; then
  [ ! -f "$RAG_DB" ] && echo "RAG-DB nicht vorhanden." && exit 0
  python3 - "$RAG_DB" << 'PYEOF'
import sys, sqlite3
db = sqlite3.connect(sys.argv[1])
n = db.execute('SELECT COUNT(*) FROM query_cache').fetchone()[0]
db.execute('DELETE FROM query_cache')
db.commit()
db.close()
print(f"✅ Query-Cache geleert ({n} Einträge entfernt | Embeddings erhalten)")
PYEOF
  exit 0
fi

# ===========================================================================
# --clear-all: Alles löschen
# ===========================================================================
if [ "${1:-}" = "--clear-all" ]; then
  [ ! -f "$RAG_DB" ] && echo "RAG-DB nicht vorhanden." && exit 0
  python3 - "$RAG_DB" << 'PYEOF'
import sys, sqlite3
db = sqlite3.connect(sys.argv[1])
n_emb = db.execute('SELECT COUNT(*) FROM chunk_embeddings').fetchone()[0]
n_cache = db.execute('SELECT COUNT(*) FROM query_cache').fetchone()[0]
db.execute('DELETE FROM chunk_embeddings')
db.execute('DELETE FROM query_cache')
db.commit()
db.close()
print(f"✅ RAG-DB geleert ({n_emb} Embeddings + {n_cache} Cache-Einträge entfernt)")
PYEOF
  exit 0
fi

# Hilfe
cat << 'HELP'
ai-rag-cache.sh — SQLite RAG-Cache + Ollama-Embeddings (v6.0 Sprint 2)

Usage:
  --init                          # DB-Schema anlegen
  --embed-chunks [registry.yaml]  # Chunk-Embeddings via Ollama generieren
  --find <query> [registry.yaml]  # Semantische Suche (Ollama + Cache + Fallback)
  --lookup <query>                # Nur Cache prüfen (kein Ollama-Call)
  --invalidate <chunk_hash>       # Veraltete Cache-Einträge löschen
  --stats                         # Cache-Statistiken
  --clear-cache                   # Query-Cache leeren (Embeddings behalten)
  --clear-all                     # Alles löschen

Embedding-Modell: nomic-embed-text (~274MB, läuft lokal via Ollama)
HELP
exit 0
