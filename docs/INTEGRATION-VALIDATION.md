# Chapter Quest V4 통합 검증 준비

## 범위와 실행 금지선

이 절차는 **별도 폐기 가능한 테스트 Supabase 프로젝트** 또는 loopback 로컬
Supabase 전용이다. 기존 운영 DB의 업그레이드 절차가 아니며, 원본 앱·기존
4개 SQL·RPC·Edge Function·Worker 구현을 다시 만들지 않는다.

원격 프로젝트가 확인되기 전에는 `--apply`, `--deploy`, `--run`을 실행하지 않는다.
스크립트는 기본 오프라인 계획만 출력하거나, 명시적 실행 플래그가 없으면 실패한다.
`supabase link`, `db reset --linked`, 기본 Cloudflare 프로젝트의 `deploy`는 사용하지 않는다.

## 먼저 실행 가능한 비밀키 없는 검사

```sh
npm ci
npm run check
npm test
npm run integration:plan
```

계획은 4개 SQL의 순서·SHA-256, 환경변수의 **이름과 설정 여부만** 출력한다.
기본 `npm run integration:apply`도 계획만 출력한다. 안전 게이트 테스트는 미확인
대상·프로젝트 불일치·TLS 검증 해제를 차단하고 비밀 값을 출력하지 않는지 확인한다.

실제 로컬 서비스 검증에는 Docker와 공식 Supabase CLI 2.75.0을 사용한다.
이 CLI는 공식 릴리스 체크섬으로 검증할 수 있다. 최신 CLI 3.1.0은 이 환경에서
읽기 전용 홈 디렉터리 초기화에 실패했다. 홈 경로나 권한을 바꾸지 말고 검증된
CLI를 사용한다.

### 로컬 Supabase (원격 키 불필요)

1. 저장소 밖의 새 작업 폴더에서 `supabase init --workdir <LOCAL_WORKDIR>`를 한다.
   먼저 폴더를 생성한다. 기존 프로젝트·컨테이너와 다른 project_id/포트를 지정한다.
2. 이번 실행은 project_id `chapter-quest-integration-local`, API 54331, DB 54332,
   Mailpit 54334, Auth site_url `http://127.0.0.1:8787`을 사용한다. 스톡 config의
   그 밖의 포트도 충돌하지 않게 분리한다. `supabase/migrations`는 아직 복사하지
   않는다. 아래 적용 스크립트가 실제 DB에 4개 파일과 검증 원장을 적용한다.
3. 저장소의 `supabase/functions`를 로컬 작업 폴더의 같은 경로에 복사하고,
   세 함수의 `verify_jwt=true` 설정을 config에 추가한다.
4. 로컬 Edge 환경 파일에 **비밀이 아닌** `APP_ORIGIN=http://127.0.0.1:8787`만
   지정한다. 내부 Supabase URL/anon/service 키는 CLI 런타임이 주입한다.
5. 로컬 DB/Auth/REST/Storage/Kong/Mailpit을 시작한다:

```sh
supabase start --workdir <LOCAL_WORKDIR> \
  --exclude studio,postgres-meta,realtime,imgproxy,supavisor,logflare,vector,edge-runtime
supabase functions serve --workdir <LOCAL_WORKDIR> --env-file <LOCAL_EDGE_ENV_FILE>
```

터미널의 status/start 출력에는 로컬 키가 포함될 수 있다. 공유 로그에 출력하지
말고 권한 0600 파일로 캡처한다. `local-run.mjs`는 status JSON을 메모리에서만
읽으며 키를 출력하거나 파일에 저장하지 않는다.

```sh
# 환경변수는 실행 파일/로컬 폴더 경로만 설정한다.
CQ_TEST_SUPABASE_CLI=<CLI_PATH> CQ_LOCAL_SUPABASE_WORKDIR=<LOCAL_WORKDIR> \
  node scripts/integration/local-run.mjs --run
```

이 실행기는 loopback API/DB만 허용하고, 원격 주소가 섞이면 거부한다. 첫 실행에는
기존 4개 마이그레이션을 적용하며, 반복 실행 시 검증 원장/해시가 같을 때만 재사용한다.
컨테이너 전체 초기화나 다른 서비스 중지는 하지 않는다.

기본 ECR 이미지 호스트가 차단된 환경에서는 CLI가 공식 지원하는
`SUPABASE_INTERNAL_IMAGE_REGISTRY=docker.io`를 사용할 수 있다. TLS·체크섬은
비활성화하지 않는다. 해당 공식 이미지 경로도 차단된다면 필요한 도메인 권한을
요청하고 로컬 전체 스택을 미검증으로 남긴다.

## 원격 테스트 프로젝트 확인 — 사용자 최소 입력

새 테스트 프로젝트 Dashboard에서 **운영과 다른 프로젝트 ref**임을 확인한다.
`integration/target.example.json`을 무시되는 `integration/target.json`으로 복사한 뒤
ref, 정확한 API URL, DB 접속 호스트를 입력한다. `confirmedDisposable`은 사람이
프로젝트 정체성과 폐기 가능성을 확인한 뒤에만 true로 바꾼다.

`CQ_TEST_TARGET_FILE`에 그 파일 경로, `CQ_TEST_CONFIRMED_PROJECT_REF`에 같은 ref를
지정한다. 이 이중 확인은 사용자의 선언을 강제하는 장치이며 클라우드 프로젝트가
운영이 아님을 자동으로 증명하지는 않는다. 다른 프로젝트 URL이나 DB 호스트는
거부된다. pooler를 쓰면 사용자명이 `postgres.<동일 ref>`여야 한다.

다음 값은 **보안 설정으로만** 제공하고 채팅·코드·터미널 출력에 붙여넣지 않는다.

| 이름 | 필요한 권한 / 사용 범위 |
| --- | --- |
| `CQ_TEST_TARGET_FILE` | 비밀 아님. 검토한 대상 파일 경로 |
| `CQ_TEST_CONFIRMED_PROJECT_REF` | 비밀 아님. 확인한 테스트 프로젝트 ref |
| `CQ_TEST_SUPABASE_ANON_KEY` | 테스트 프로젝트 공개 키. 실제 권한은 사용자 JWT/RLS가 결정 |
| `CQ_TEST_SERVICE_ROLE_KEY` | **테스트만** Auth Admin 임시 계정 생성·삭제, Storage 테스트 파일 정리 |
| `CQ_TEST_DATABASE_URL` | 테스트 DB의 마이그레이션/함수·트리거·RLS 생성, 테스트 부모 역할 설정과 fixture 정리 권한 |
| `CQ_TEST_OPENAI_API_KEY` | 선택. 테스트 모델 호출 권한과 제한된 예산. 실제 모델 검증 때만 필요 |
| `CQ_TEST_INVITE_EMAIL` | 선택. 사용자가 관리하는 테스트 수신함. 이메일 초대 요청 검증에만 사용 |
| `SUPABASE_ACCESS_TOKEN` | Edge CLI 배포 때만. 테스트 프로젝트에 함수 배포 권한이 있는 계정/조직의 토큰 |
| `CQ_TEST_SUPABASE_CLI` | 비밀 아님. 확인한 CLI 실행 파일 경로 |
| `CQ_TEST_PARENT_ACCESS_TOKEN` | 선택. 독립 AI 검증 때만 필요한 테스트 부모의 단기 JWT. 통합 probe는 자체 생성하므로 불필요 |

기본 API/DB 통합에는 공개 키·테스트 service 키·테스트 DB 접속 정보가 필요하다.
Cloudflare API 토큰은 **필요 없다**. AI Worker는 로컬로 실행할 수 있다.
Edge를 사용자가 직접 테스트 프로젝트에 설치하면 이 채팅에 Supabase PAT도 필요 없다.
DB URL의 암호는 로컬 pg 클라이언트가 사용할 수 있는 보안 런타임 값이어야 한다.
HTTP 프록시의 치환용 placeholder는 raw PostgreSQL 암호를 대체하지 못한다.

네트워크: `<test-ref>.supabase.co` HTTPS, CLI 배포 시 `api.supabase.com` HTTPS,
모델 검증 시 `api.openai.com` HTTPS가 필요하다. DB 호스트/포트는 별도 TCP 접근과
클라이언트 경로가 필요하며, HTTP 도메인 허용만으로 PostgreSQL 연결이 되지는 않는다.
TLS 검증을 유지한다. 이 환경에서 TCP가 지원되지 않으면 지원되는 연결 경로나
테스트 관리자 PC에서 같은 스크립트를 사용한다. 주소 확인 전에는 정책을 추측해 바꾸지 않는다.

## 적용 순서

### 1. SQL / Auth / Storage / RLS / RPC

```sh
npm run integration:apply -- --apply --fresh-test-only
```

실행 전 대상 확인과 DB 호스트·ref·TLS 검사를 한다. `cq_private`·검증 원장이 이미 있거나 Auth 사용자·Storage 객체·일반 public 테이블이
있으면 기준 스키마를 덮어쓰지 않고 중단한다. 기존 데이터가 있는 프로젝트는 이 기준
스키마 적용 경로의 대상이 아니다. 파일 순서는 다음과 같다:

1. `202611130001_p0_contract.sql`: profiles·학생 연결·초대·승인·배정·제출·피드백, RLS/RPC, 신규 Auth 사용자 trigger
2. `202611130002_storage.sql`: 비공개 버킷 2개·Storage 정책·서비스 전용 PDF 검증
3. `202611130003_account_invites.sql`: 부모별 계정 초대 요청량 제한
4. `202611160001_text_chapters.sql`: TXT 원문과 기존 챕터 ID 연결·승인 원문 일치 검사

성공 후 `cq_test_control`에 대상 ref와 적용 해시를 기록한다. 일부 파일 실패 시
이전 파일은 이미 적용됐을 수 있으므로 자동 reset/재실행하지 않는다. 실패 파일명을
보고하고 새 폐기 가능한 프로젝트에서 재검토한다. 검증 원장이 없는 프로젝트에서
probe를 실행할 수 없다.

### 2. Auth 이메일과 Edge

Auth site URL과 허용 redirect URL을 테스트 앱의 정확한 origin으로 제한한다.
SMTP는 테스트 수신함 또는 로컬 Mailpit으로 설정한다. 전달 확인·비밀번호 설정
콜백은 HTTP 요청 성공만으로 완료 처리하지 않는다.

래퍼는 확인한 대상의 정확한 테스트 앱 origin으로 `APP_ORIGIN`을 설정한다.
수동으로 설치하는 경우 같은 설정을 테스트 Edge 환경에 지정한다.
`SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`는 Supabase가
함수 안에 주입하는 서버 설정이며 브라우저 코드에 복사하지 않는다. 설정 후에만:

```sh
node scripts/integration/deploy-functions.mjs --deploy
```

래퍼는 확인된 ref를 설정·배포 명령마다 `--project-ref`로 전달하며 `APP_ORIGIN` 설정과
세 함수만 대상으로 한다.
저장소의 `verify_jwt=true`를 유지하고 `--no-verify-jwt`로 우회하지 않는다.
새 publishable/secret 키를 쓰는 경우 JWT gateway 호환성을 실제 검증해야 한다.
실패 시 인증 검사를 끄지 말고 호환되는 테스트 API 키/JWT 경로를 확인한다.

### 3. 실제 API 통합 probe

```sh
npm run integration:probe -- --run
```

매 실행은 임시 Auth 사용자 4명을 만들고 그중 2명만 테스트 부모로 설정한다.
기존 사용자를 승격하거나 기존 데이터를 초기화하지 않는다. 다음을 실제 HTTP로 검사한다:

- Auth signup trigger·비밀번호 로그인·갱신
- 초대 사용·재사용 차단·부모 승인·다른 부모/학생 접근 차단
- Edge 소유권 확인·서명 PDF 업로드·실제 바이트 검증·서비스 전용 finalizer
- 같은 챕터 UUID·중복 게시 방지·정답 비노출·서명 PDF 다운로드 해시
- Storage 녹음 RLS·중복 제출 차단·피드백 비공개/공개
- TXT 원문·승인·배정·조회·연결 해제 후 새 접근 차단

테스트의 오디오 바이트는 Storage 전송 fixture이며 실제 녹음/재생 품질을 증명하지 않는다.
probe는 UI의 최종 제출 잠금을 해제하지 않고 서버 RPC 계약만 검사한다.

`CQ_TEST_INVITE_EMAIL`이 없으면 실제 이메일 요청을 실행하지 않고 명시적으로 미실행
기록한다. 지정하면 계정 초대 요청까지만 검사하며, 메일 도착·링크·비밀번호 설정은
사용자가 수신함에서 확인해야 한다. 지정 수신함의 계정은 임의로 삭제하지 않는다.

finally에서 이번 실행의 정확한 파일 경로와 임시 사용자 UUID만 정리한다.
비밀·토큰·암호·서명 URL 없이 `.integration/report-<run>.json`에 결과를 기록한다.
정리에 실패하면 실패 상태와 남은 fixture 식별자를 남기며 통과로 처리하지 않는다.
이미 발급된 PDF URL은 짧은 만료까지 유효할 수 있으므로 revoke는 **새 발급 차단**을 검사한다.

## AI Worker 실제 모델 검증 (별도 비용 동의)

```sh
node scripts/integration/worker-vars.mjs --write
# 위 명령은 확인된 TEST 설정만 integration/.dev.vars(0600)에 기록하며 덮어쓰지 않는다.
wrangler dev --config integration/wrangler.test.jsonc --local --ip 127.0.0.1 --port 8787
npm run integration:probe -- --run --allow-model-cost
```

프로덕션 이름과 다른 `chapter-quest-v4-integration` 설정을 사용한다. 로컬 Worker만
시작하며 배포 명령은 필요 없다. provider 키는 프로세스 인자·브라우저 설정에 넣지 않는다.
실제 호출은 합성 원문 하나를 사용하며 아동 학습 데이터·운영 자료를 전송하지 않는다.
실제 모델 schema·독해/추론 혼합을 검사하지만 사실성·연령 적합성·정답 품질은
부모 검토가 필요하다. 생성된 문제를 자동 승인하거나 학습에 배정하지 않는다.

원하는 경우 기존 테스트 부모 JWT로 독립 호출도 가능하다:

```sh
npm run integration:model -- --run --allow-model-cost
```

요금/키 설정이 없으면 모델 단계를 완료로 표시하지 않는다. 기본 probe에는 모델
호출이 없다. 원격 Worker 배포가 꼭 필요하면 별도 테스트 계정/이름·권한을 확인한
후 별도 승인 범위에서 수행한다. 이 문서의 절차는 운영 배포를 포함하지 않는다.

## 최종 수동 통과 조건

- 테스트 이메일 도착 → 링크 → 비밀번호 설정 → 부모 코드 연결·승인
- 실제 학생 기기 PDF/TXT 읽기, 마이크 허용·녹음 재생·재로그인 복구
- 검토한 AI 문항의 정답·난이도 확인
- 서버 제출 복구와 동시성 시험 후에만 UI 제출 잠금 해제 검토

로컬 자동 검사, 실제 로컬 서비스 검사, hosted 테스트, 실제 모델, 수동 기기 검증은
서로 다른 결과다. 실행하지 않은 단계는 미검증으로 보고한다.
