# Hermes 로컬 송무 검색 워크플로우 설명서

작성일: 2026-05-18 22:37 KST

이 문서는 `jurisupport-plugins`를 Hermes Agent에서 로컬 송무/법률 검색 보조 도구로 쓰기 위한 설명서입니다. 현재 구성은 **포크 브랜치 검증용**이며, upstream PR을 열기 전 실제 데이터로 품질을 확인하는 단계입니다.

## 1. 전체 구조

현재 구성은 다음 4개 층으로 나뉩니다.

1. **로컬 임베딩 서버**
   - endpoint: `http://127.0.0.1:18768/v1/embeddings`
   - model: `intfloat/multilingual-e5-small`
   - OpenAI `/v1/embeddings` 호환 API 제공

2. **로컬 검색 서버**
   - legal-books: `http://127.0.0.1:18766`
   - case-records: `http://127.0.0.1:18767`

3. **Hermes skills**
   - 설치 위치: `~/.hermes/skills/legal/`
   - 법률서적 검색, 과거 사건 검색, 준비서면 작성 프로토콜 등을 Hermes가 자동으로 참고하도록 함

4. **운영/검증 브랜치**
   - repo: `https://github.com/virtualite9-ctrl/jurisupport-plugins`
   - branch: `hermes-local-llm-embeddings`
   - upstream PR은 아직 열지 않음

## 2. 설치된 주요 경로

### 코드 저장소

```bash
/Users/joo/.openclaw/workspace/jurisupport-plugins
```

### 로컬 embedding 서버

```bash
/Users/joo/jurisupport-embedding-server
```

관리 명령:

```bash
cd ~/jurisupport-embedding-server
./server.sh status
./server.sh restart
./server.sh stop
./server.sh start
```

launchd 등록 파일:

```bash
~/Library/LaunchAgents/com.jurisupport.embedding-server.plist
```

### legal-books

```bash
~/legal-books
```

관리 명령:

```bash
~/legal-books/scripts/server.sh status
~/legal-books/scripts/server.sh restart
~/legal-books/scripts/add_book.sh
```

### case-records

```bash
~/case-records
```

관리 명령:

```bash
~/case-records/scripts/server.sh status
~/case-records/scripts/server.sh restart
~/case-records/scripts/ingest_case.sh
~/case-records/scripts/ingest_all.sh --root <사건기록_루트>
```

### Hermes skills

```bash
~/.hermes/skills/legal/
```

설치된 skills:

```text
legal-books
case-records
brief-protocol
case-index
beopgoeul-search
lbox-guide
cold-start-interview
```

### 운영 계획 문서

```bash
~/.hermes/legal-jurisupport-rollout-plan.md
```

## 3. 상태 점검

작업 전 다음 health check를 먼저 실행합니다.

```bash
curl -s http://127.0.0.1:18768/health
curl -s http://127.0.0.1:18766/health
curl -s http://127.0.0.1:18767/health
```

정상 예시:

```json
{"status":"ok","default_model":"intfloat/multilingual-e5-small","loaded_models":["intfloat/multilingual-e5-small"]}
{"status":"ok","books":1,"chunks":1}
{"status":"ok","cases":1,"documents":1,"chunks":1}
```

주의:

- `books: 0`이면 legal-books 검색을 하지 말고 먼저 책을 추가합니다.
- `cases: 0`이면 case-records 검색을 하지 말고 먼저 사건기록을 추가합니다.
- 현재 `books=1`, `cases=1`은 smoke-test 데이터일 수 있으므로 실무 품질 판단에는 부족합니다.

## 4. Hermes에서 쓰는 법

### 명시적으로 skill 불러오기

Telegram 또는 Hermes CLI에서 다음처럼 사용할 수 있습니다.

```text
/skill legal-books
/skill case-records
/skill brief-protocol
```

또는 질문에 자연어로 요청해도 됩니다.

예시:

```text
소멸시효 완성 후 채무승인 쟁점에 대해 교과서 검색해줘.
```

```text
비슷한 사건기록이 있는지 case-records에서 찾아줘.
```

```text
이 사건 준비서면 작성하려고 해. 먼저 목차까지만 만들어줘.
```

## 5. legal-books 사용법

법률서적/교과서 기반으로 법리를 확인할 때 사용합니다.

### 검색 API

```bash
curl -s -X POST http://127.0.0.1:18766/search \
  -H 'Content-Type: application/json' \
  -d '{"query":"소멸시효 채무승인 시효이익 포기","top_k":5}'
```

### Hermes 요청 예시

```text
legal-books에서 “소멸시효 채무승인 시효이익 포기”를 검색하고,
저자·서명·페이지를 붙여 요지만 정리해줘.
```

### 인용 원칙

- 저자, 서명, 판, 출판사/연도, 페이지를 가능한 한 모두 적습니다.
- 직접인용은 `chunk_text`와 글자 단위로 일치할 때만 합니다.
- 정확히 일치하지 않으면 간접인용으로 정리합니다.
- 검색 결과가 없으면 출처를 꾸며내지 않습니다.

## 6. case-records 사용법

과거 사건기록에서 유사 사건, 기존 주장 구조, 상대방 반박, 법원 판단을 찾을 때 사용합니다.

### 검색 API

```bash
curl -s -X POST http://127.0.0.1:18767/search \
  -H 'Content-Type: application/json' \
  -d '{"query":"소멸시효 항변 채무승인 준비서면","top_k":5}'
```

문서 종류를 좁히고 싶으면 `filters`를 사용합니다.

```bash
curl -s -X POST http://127.0.0.1:18767/search \
  -H 'Content-Type: application/json' \
  -d '{"query":"임대차 보증금 반환 지연손해금","top_k":5,"filters":{"doc_type":"준비서면"}}'
```

### Hermes 요청 예시

```text
case-records에서 “임대차 보증금 반환 지연손해금” 관련 과거 준비서면을 찾아줘.
사건번호, 사건명, 문서종류, 일자를 같이 표시해줘.
```

### 인용 원칙

- 사건번호, 사건명, 문서종류, 일자, 작성자 역할을 표시합니다.
- 과거 사건은 참고자료일 뿐 현재 사건에 그대로 일반화하지 않습니다.
- 필요한 경우 “현재 사건의 사실관계가 다를 수 있으므로 원기록 확인 필요”라고 표시합니다.

## 7. 실제 데이터 넣는 법

### 7-1. 교과서/법률서적 추가

```bash
~/legal-books/scripts/add_book.sh
~/legal-books/scripts/server.sh restart
curl -s http://127.0.0.1:18766/health
```

권장 시작량:

- 교과서 또는 법률서적 1~3권
- OCR 품질이 좋은 PDF 또는 텍스트 우선

검증 쿼리:

```bash
curl -s -X POST http://127.0.0.1:18766/search \
  -H 'Content-Type: application/json' \
  -d '{"query":"소멸시효 채무승인 시효이익 포기","top_k":5}'
```

합격 기준:

- 관련 chunk가 상위 5개 안에 나옵니다.
- 페이지와 서지 metadata가 인용 가능하게 보존됩니다.

### 7-2. 사건기록 추가

```bash
~/case-records/scripts/ingest_case.sh
# 또는 일괄 처리
~/case-records/scripts/ingest_all.sh --root <사건기록_루트>
~/case-records/scripts/server.sh restart
curl -s http://127.0.0.1:18767/health
```

권장 시작량:

- 과거 사건 5~10건
- 준비서면, 답변서, 판결문 중 최소 1개 이상

검증 쿼리:

```bash
curl -s -X POST http://127.0.0.1:18767/search \
  -H 'Content-Type: application/json' \
  -d '{"query":"소멸시효 항변 채무승인 준비서면","top_k":5}'
```

합격 기준:

- 실제로 유사한 사건/문서가 상위 결과에 나옵니다.
- 사건번호, 사건명, 문서종류, 일자가 유지됩니다.

## 8. 준비서면 작성 workflow

Hermes에서는 `brief-protocol` skill을 기준으로 갑니다.

### 원칙

준비서면 작성은 다음 순서로 진행합니다.

1. 인테이크
   - 사건번호/사건명
   - 서면 유형
   - 제출기한/기일
   - 당사자 지위
   - 특별 지시사항

2. 기록·교과서 검색
   - `case-records`: 비슷한 사건/과거 서면
   - `legal-books`: 법리/교과서 근거

3. 목차 작성
   - 여기서 사용자 승인 필요
   - 승인 전 본문 작성 금지

4. 본문 초안 작성

5. 인용 검증
   - 법령 인용
   - 판결 인용
   - 교과서 인용
   - 직접인용

6. 최종본/PDF 준비
   - 법원 전자제출은 사용자가 직접 수행

### Hermes 요청 예시

```text
/skill brief-protocol

2026가단00000 사건 준비서면을 만들려고 해.
쟁점은 소멸시효 완성 후 채무승인이야.
먼저 legal-books와 case-records를 검색하고,
본문은 쓰지 말고 목차 초안까지만 만들어줘.
```

## 9. 인용 검증 정책

최종 법률문서에는 검증되지 않은 인용을 넣지 않습니다.

### 법령

- Korean-law MCP 또는 법제처 기반 도구로 조문 실존 여부를 확인합니다.
- 조문 번호와 제목이 맞는지 확인합니다.

### 판결

- Korean-law 검색으로 1차 확인합니다.
- 필요 시 `beopgoeul-search`로 법고을 검색을 보조합니다.
- 사건번호, 법원, 선고일이 일치해야 합니다.

### LBox

- `lbox.kr`는 자동화하지 않습니다.
- Hermes는 검색 키워드만 제안합니다.
- 사용자가 직접 로그인해 PDF를 내려받고, 그 파일을 제공하면 분석합니다.

### 직접인용

- 원문과 글자 단위로 일치할 때만 따옴표 직접인용을 사용합니다.
- 일치 확인이 안 되면 간접인용으로 바꿉니다.

## 10. 안전 원칙

다음은 자동화하지 않습니다.

- 법원 전자제출
- 전자서명
- 법원/전자소송 사이트 로그인
- 이메일 발송
- LBox 자동 접속
- 사용자의 최종 승인 없는 문서 상태 변경
- 민감 사건기록 삭제

실제 사건기록을 넣기 전에는 개인정보/민감정보 처리 범위를 먼저 확인합니다.

## 11. 장애 대응

### 검색 서버가 응답하지 않을 때

```bash
~/legal-books/scripts/server.sh status
~/legal-books/scripts/server.sh restart

~/case-records/scripts/server.sh status
~/case-records/scripts/server.sh restart
```

### embedding 서버가 응답하지 않을 때

```bash
cd ~/jurisupport-embedding-server
./server.sh status
./server.sh restart
```

launchd 상태 확인:

```bash
launchctl print gui/$(id -u)/com.jurisupport.embedding-server
```

### 검색 결과가 이상할 때

1. health에서 `books`, `cases`, `chunks` 수 확인
2. OCR 텍스트 품질 확인
3. 너무 긴 쿼리 대신 핵심 법리 키워드로 재검색
4. `top_k`를 5 또는 10으로 늘려 비교
5. metadata 누락 여부 확인

## 12. 운영 판단 기준

### 계속 포크 브랜치로 운영할 조건

- 로컬 임베딩/검색 환경이 개인 환경에 강하게 묶여 있음
- 실제 사건기록·사무소 workflow가 private 성격임
- upstream에 바로 일반화하기 어려움

### upstream PR을 고려할 조건

- clean macOS/WSL 설치 테스트 통과
- provider abstraction이 범용적으로 정리됨
- 문서가 제3자 기준으로 충분함
- Gemini 의존 제거/대체 방식이 upstream 방향과 맞음

## 13. 빠른 점검 명령 모음

```bash
# Git 브랜치
cd /Users/joo/.openclaw/workspace/jurisupport-plugins
git status -sb
git log --oneline -3

# 서비스 health
curl -s http://127.0.0.1:18768/health
curl -s http://127.0.0.1:18766/health
curl -s http://127.0.0.1:18767/health

# legal-books 검색
curl -s -X POST http://127.0.0.1:18766/search \
  -H 'Content-Type: application/json' \
  -d '{"query":"소멸시효 채무승인 시효이익 포기","top_k":5}'

# case-records 검색
curl -s -X POST http://127.0.0.1:18767/search \
  -H 'Content-Type: application/json' \
  -d '{"query":"소멸시효 항변 채무승인 준비서면","top_k":5}'

# Hermes skills 확인
hermes skills list | grep -E 'legal-books|case-records|brief-protocol|case-index|beopgoeul|lbox'
```

## 14. 추천 다음 단계

1. 교과서/법률서적 1권을 `legal-books`에 추가
2. 과거 사건기록 2~3건을 `case-records`에 추가
3. 위 예시 쿼리로 검색 품질 확인
4. `brief-protocol`로 준비서면 목차 dry-run
5. 결과가 좋으면 사건기록 5~10건으로 확대
6. 그 후 upstream PR 여부 결정
