#!/usr/bin/env bash
# case-records toolkit installer (Mac/Linux)
#
# Same structure as legal-books but for case files. Port 8767.

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[info]${NC} $*"; }
warn()  { echo -e "${YELLOW}[warn]${NC} $*"; }
error() { echo -e "${RED}[error]${NC} $*"; exit 1; }

OS="$(uname -s)"
case "$OS" in
  Darwin*) PLATFORM="mac" ;;
  Linux*)  PLATFORM="linux" ;;
  *) error "지원하지 않는 OS: $OS (macOS/Linux만 지원)" ;;
esac
info "플랫폼: $PLATFORM"

# Prerequisites
command -v curl >/dev/null || error "curl 필요"
select_python() {
  local candidate ver major minor
  for candidate in python3.13 python3.12 python3.11 python3.10 python3; do
    if ! command -v "$candidate" >/dev/null 2>&1; then
      continue
    fi
    ver=$("$candidate" -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
    major=${ver%%.*}; minor=${ver#*.}
    if [[ "$major" -eq 3 && "$minor" -ge 10 && "$minor" -le 13 ]]; then
      printf '%s' "$candidate"
      return 0
    fi
  done
  return 1
}
PYTHON_BIN=$(select_python) || error "Python 3.10~3.13 필요. Python 3.14는 일부 고정 패키지(pydantic-core)가 아직 미지원입니다."
info "Python 사용: $PYTHON_BIN ($($PYTHON_BIN --version 2>&1))"

ROOT="$HOME/case-records"
info "디렉토리 생성: $ROOT"
mkdir -p "$ROOT/cases" "$ROOT/db" "$ROOT/server" "$ROOT/scripts" "$ROOT/logs"

info "Python 가상환경 생성"
# Ubuntu/Debian은 python3-venv 별도 설치 필요
if [[ "$PLATFORM" == "linux" ]] && ! "$PYTHON_BIN" -c "import ensurepip" 2>/dev/null; then
  info "python3-venv 자동 설치 중..."
  PYV=$("$PYTHON_BIN" -c 'import sys; print(f"python3.{sys.version_info.minor}-venv")')
  sudo apt-get install -y "$PYV" python3-venv 2>&1 | tail -3 || \
    sudo apt-get install -y python3-venv 2>&1 | tail -3
  "$PYTHON_BIN" -c "import ensurepip" 2>/dev/null || error "python3-venv 설치 실패. 수동: sudo apt install python3-venv"
fi
"$PYTHON_BIN" -m venv "$ROOT/.venv"
# shellcheck disable=SC1091
source "$ROOT/.venv/bin/activate"
pip install --quiet --upgrade pip
pip install --quiet \
  fastapi==0.115.0 uvicorn==0.31.0 pydantic==2.9.2 \
  sqlite-utils==3.37 pypdf==5.0.1 \
  numpy==1.26.4 python-dotenv==1.0.1 python-docx==1.1.2

info "SQLite DB 초기화"
python3 - <<'PY'
import sqlite3, os
ROOT = os.path.expanduser("~/case-records")
db_path = os.path.join(ROOT, "db", "cases_fts.db")
con = sqlite3.connect(db_path)
con.executescript("""
CREATE TABLE IF NOT EXISTS cases (
  case_id TEXT PRIMARY KEY,
  case_name TEXT,
  status TEXT,            -- 종결/진행중/중지
  result TEXT,            -- 전부승소/일부승소/패소/조정/취하 등
  court TEXT,
  added_at TEXT DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE IF NOT EXISTS documents (
  doc_id TEXT PRIMARY KEY,
  case_id TEXT NOT NULL REFERENCES cases(case_id),
  doc_type TEXT,          -- 소장/답변서/준비서면/판결문 등
  doc_date TEXT,
  author_role TEXT,       -- 우리측/상대측/법원/원고/피고
  source_file TEXT
);
CREATE TABLE IF NOT EXISTS chunks (
  chunk_id TEXT PRIMARY KEY,
  doc_id TEXT NOT NULL REFERENCES documents(doc_id),
  case_id TEXT NOT NULL REFERENCES cases(case_id),
  chunk_text TEXT NOT NULL,
  embedding BLOB
);
CREATE VIRTUAL TABLE IF NOT EXISTS chunks_fts USING fts5(
  chunk_text, chunk_id UNINDEXED, case_id UNINDEXED, doc_id UNINDEXED,
  content='chunks', content_rowid='rowid', tokenize='unicode61'
);
""")
con.commit()
con.close()
print("DB 초기화 완료")
PY

# Local embedding endpoint config (OpenAI-compatible)
SECRETS="$HOME/.jurisupport/secrets.env"
mkdir -p "$(dirname "$SECRETS")"; chmod 700 "$(dirname "$SECRETS")"
touch "$SECRETS"; chmod 600 "$SECRETS"
ensure_secret() {
  local key="$1" value="$2"
  if grep -q "^${key}=" "$SECRETS"; then
    info "${key} 이미 설정됨: $SECRETS"
  else
    echo "${key}=${value}" >> "$SECRETS"
    info "${key} 기본값 저장: ${value}"
  fi
}
ensure_secret "JURISUPPORT_EMBEDDING_PROVIDER" "openai"
ensure_secret "JURISUPPORT_EMBEDDING_BASE_URL" "http://127.0.0.1:3333/v1"
ensure_secret "JURISUPPORT_EMBEDDING_MODEL" "local-embedding"
ensure_secret "JURISUPPORT_EMBEDDING_API_KEY" "no-key-required"
ensure_secret "JURISUPPORT_CASE_RECORDS_PORT" "18767"
warn "로컬 엔드포인트가 /v1/embeddings를 제공해야 의미 검색이 작동합니다."
warn "미지원 시 임시 fallback: JURISUPPORT_EMBEDDING_PROVIDER=hash"

TOOLKIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cp "$TOOLKIT_DIR/server/server.py" "$ROOT/server/server.py"
cp "$TOOLKIT_DIR/../shared/embedding_provider.py" "$ROOT/server/embedding_provider.py"
cp "$TOOLKIT_DIR/scripts/"*.{sh,py} "$ROOT/scripts/"
cp "$TOOLKIT_DIR/../shared/embedding_provider.py" "$ROOT/scripts/embedding_provider.py"
chmod +x "$ROOT/scripts/"*.sh

# Install skill
SKILL_DST="$HOME/.claude/skills/case-records"
mkdir -p "$SKILL_DST"
cp "$TOOLKIT_DIR/../../skills/case-records/SKILL.md" "$SKILL_DST/SKILL.md"

# Start server
"$ROOT/scripts/server.sh" start
sleep 2
CASE_RECORDS_PORT=$(grep -E "^JURISUPPORT_CASE_RECORDS_PORT=" "$SECRETS" | tail -1 | cut -d= -f2-)
CASE_RECORDS_PORT="${CASE_RECORDS_PORT:-18767}"
if curl -sf "http://localhost:${CASE_RECORDS_PORT}/health" >/dev/null; then
  info "서버 실행 중 (포트 ${CASE_RECORDS_PORT})"
else
  warn "서버 시작 실패. 로그 확인: $ROOT/logs/server.log"
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}case-records toolkit 설치 완료${NC}"
echo -e "${GREEN}========================================${NC}"
cat <<EOF

다음 단계:
  1. 첫 사건 인덱싱:
       ~/case-records/scripts/ingest_case.sh \\
         --case-dir ~/사건/2018가단11111_홍○○_대여금 \\
         --case-id 2018가단11111 \\
         --case-name "홍○○ 대여금" \\
         --status 종결 --result 전부승소

  2. 또는 ~/사건/ 아래 모든 사건 일괄 인덱싱:
       ~/case-records/scripts/ingest_all.sh --root ~/사건

  3. 검색 테스트:
       curl -X POST http://localhost:18767/search \\
         -H 'Content-Type: application/json' \\
         -d '{"query":"보증금","top_k":3}'

가이드: ~/jurisupport-plugins/guides/03_case_records.md
EOF
