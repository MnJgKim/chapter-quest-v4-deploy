# Chapter Quest V4 — 검증된 통합 테스트 및 운영 전 승인 게이트 (2026-11-14)

## 검증 근거
- 검증 브랜치: `work/v4-safe-integration-20261113`
- 통과 커밋: `58296b8388b193937036e03888391a3281b7dd24`
- GitHub Actions 실행: https://github.com/MnJgKim/chapter-quest-v4-deploy/actions/runs/43567630862
- 실행 결과: **success**. `npm test`, `npm run build`, 현재 V4 브라우저 스모크, 격리된 로컬 Supabase Auth/PostgreSQL/Storage/Edge 통합 테스트 모두 성공.
- 로컬 통합 검증: TXT 37개, PDF 37개, 부분 페이지 범위 48개, 전체 PDF 42개 = **총 164개 성공**. 4개 시나리오 모두 브라우저 page_errors 및 blocked_requests 없음.
- 검증 대상: 합성 사용자, 합성 PDF/음성, 격리 로컬 Supabase. 실제 운영 데이터/AI 호출 없음.
- 포함 기능: 초대·승인, 원본 등록, 문제 승인·배정, 학생별 별도 공개, 비공개 접근 차단, PDF 서명 링크, 모바일/태블릿 뷰포트, 입력·제출, 녹음·피드백, 두 학생 데이터 격리, 타 부모·미배정 계정 권한 차단.

## 여전히 미검증 또는 미완료
1. 운영 Cloudflare의 실제 배포 버전/설정/계정 요금제, 직전 배포 및 복원 경로 확인.
2. 운영 Supabase의 변경 전 **독립적이고 복구 가능한** DB/Auth/Storage 백업과 Edge 소스/권한 스냅샷 검증. Git 커밋은 DB 백업이 아님.
3. 운영 DB의 SQL/RPC/RLS와 후보 마이그레이션 간 호환성 재확인. 로컬 테스트 통과가 운영 변경 허가를 의미하지 않음.
4. 실제 Galaxy 휴대폰/태블릿에서 최종 후보 버전으로 PDF·녹음 권한·제출·피드백 실기기 인수검사.
5. 서우 실제 학생 계정과 첫 학습 원본/문제의 부모 최종 확인. 2026-11-23 첫 수업 원본은 사용자가 기존 11쪽 전체 사용으로 확인한 The Knight at Dawn / The Dark Woods. 원본을 중복 업로드하거나 학생 배정·공개를 임의 변경하지 않음.
6. 운영 적용 파일별 변경 목록·위험·복구 절차에 대한 **명시적 사용자 승인** 후에만 배포/DB 변경/병합 수행.

## 범위와 금지
- 현재 작업은 Draft PR #3의 검증 후보이며 `main`에 병합하지 않음.
- 운영 Cloudflare, Supabase 스키마/행/Storage/Auth, 실제 학생 배정·공개·제출, 유료 AI 설정을 변경하지 않음.
- 운영 적용에 `app/local-supabase/supabase/migrations/20261114000000_cq_local_lesson_release.sql` 등 로컬 테스트용 bootstrap 마이그레이션을 무분별하게 포함하지 않음.
- 오래된 `app/LAUNCH_READINESS.md`의 '게시 0건/배정 0건'과 과거 테스트 수치는 최신 운영 상태를 뜻하지 않음. 운영 현황은 별도 읽기 전용 조회로 다시 확인해야 함.

## 운영 Supabase 읽기 전용 호환성 점검 (2026-11-14)
프로젝트 `ftffxetmqditfqdvzjdd`에 대해 `pg_proc`, `pg_class` 및 권한 조회만 수행. DDL/DML 없음.

- **존재·authenticated 실행 가능·anon 실행 불가**: `cq_v4_my_released_chapters()`, `cq_v4_parent_schedule_lesson(uuid,uuid,date)`, `cq_v4_parent_set_lesson_release(uuid,uuid,boolean)`, `cq_v4_submit_answers(uuid,jsonb)`. 네 함수 모두 SECURITY DEFINER이므로 내부 권한 검사와 입력 검증이 필수이며, 이 조회만으로 안전성을 증명하지는 않음.
- **운영에 없음**: `cq_v4_parent_lesson`, `cq_v4_commit_pdf_range`, `cq_v4_register_range_approval_once` (public 스키마에서 모든 인자 조합을 검색). 후보 프런트/Edge가 호출한다면 배포 전 명시적 승인과 SQL 호환 적용 필요.
- **테이블 존재·RLS 활성화**: `cq_v4_activities`, `cq_v4_lesson_schedule`, `cq_v4_pdf_assignments`, `cq_v4_pdf_chapters`, `cq_v4_pdf_enrollments`. `cq_v4_pdf_page_ranges`는 없음.
- `anon`은 위 테이블 모두 SELECT 권한 없음. `authenticated`은 activities/schedule SELECT 권한 없고, assignments/chapters/enrollments는 SELECT 권한 있으나 RLS 적용. 실제 row 정책은 별도 검증 필요.
- **배포 차단 요인**: 부분 PDF 범위·부모 상세 결과를 사용하는 후보 기능과 운영 RPC 간 불일치. 새 SQL 두 건의 정확한 적용 대상·복구 방식 및 Edge 버전 동기화 승인 필요.
- 운영 DB 백업의 독립적 복원 가능 여부와 Cloudflare 직전 배포 정보는 **미확인**.

## 운영 구성 인벤토리 — 읽기 전용 재확인 (2026-11-14)
- Supabase 프로젝트 `ftffxetmqditfqdvzjdd` (표시명 `english-v3b-test`), `ACTIVE_HEALTHY`, PostgreSQL `17.11`, 리전 `ap-northeast-1`.
- 운영 Edge `cq-v4-pdf-parent`: **v3**, `ACTIVE`, `verify_jwt=true`, sha256 `4282f51fb8e37b8975447f0556661b9430c2805a62d34b0927e78e77a3ed2248`.
- 운영 Edge `cq-v4-pdf-link`: **v1**, `ACTIVE`, `verify_jwt=true`, sha256 `c1cf8df7a8439698833f89afd1a7b44de9bdd4413755de67f9ab5bb70cfa46a9`.
- `get_edge_function`으로 현재 두 함수 소스를 읽기 전용 확인함. 비밀 환경변수/학생 파일은 다운로드하거나 기록하지 않음.
- 운영 마이그레이션 이력 총 **6건**: `20261110114235`, `20261113103229`, `20261113103331`, `20261113103348`, `20261113103359`, `20261113103519`.
- 운영에 후보 신규 부모 상세 결과 RPC 및 PDF 범위 SQL이 설치됐다고 가정하지 말 것. 후보 Edge를 먼저 교체하면 누락된 RPC로 실패할 수 있음.
- 위 Edge SHA와 버전은 **복구 대상 식별자**일 뿐이며, 별도의 백업 파일·실제 재배포/복원 권한·Cloudflare 배포 롤백을 검증한 것은 아님.
- 현재 **배포 승인 요청 전 미해결 차단**: 운영 DB/Auth/Storage 백업 및 복원 접근 검증, Cloudflare 배포 버전/복구 경로 확인, SQL/Edge 호환 순서 확정, 실기기 최종 수락.

## Edge 소스와 후보 SQL의 정확한 차이 (읽기 전용 비교)
운영 Edge 함수 소스는 `get_edge_function`으로 읽고, 동일 경로의 Draft PR 후보 파일과 비교함. **양쪽 모두 서로 다르며 운영 적용 전 버전 정합성 필요.**

| 항목 | 운영 | 후보 | 배포 전 처리 |
|---|---|---|---|
| 부모 Edge `cq-v4-pdf-parent` | v3, index.ts 12,602자 | index.ts 17,135자 | 신규 `create_range`, `download_url` 경로 존재. `cq_v4_commit_pdf_range` RPC 사용. 운영 함수는 해당 경로/RPC 사용하지 않음 |
| 학생 Edge `cq-v4-pdf-link` | v1, index.ts 3,848자 | index.ts 5,767자 | 후보는 `cq_v4_my_chapter_activities` RPC 참조; 기존 운영 함수는 참조하지 않음. 게시·학생 권한 검증 일치 여부 확인 |
| 부모 상세 결과 SQL | `cq_v4_parent_lesson` 없음 | `20261111013217_cq_parent_lesson_context.sql` | 신규 SECURITY DEFINER 함수; 소유자·관리자 확인, published activity/approval 조인 |
| PDF 범위 SQL | `cq_v4_pdf_page_ranges`, `cq_v4_commit_pdf_range`, `cq_v4_register_range_approval_once` 없음 | `20261111233341_cq_verified_pdf_ranges.sql` | 신규 테이블+두 함수. 원본/파생 PDF 참조와 승인/게시 의존성 존재 |
| 기존 의존 RPC | `cq_is_admin`, `cq_v4_parent_submissions`, `cq_v4_register_approval_once`, `cq_v4_bind_verified_pdf` 모두 존재 | 후보 코드에서 참조 | 운영에서 이름·인자 존재 확인. 세부 동작과 권한은 별도 검토 필요 |

**권장 릴리스 의존 순서(승인 전 설계, 실행 아님):**
1. DB/Auth/Storage 독립 복구 지점과 Edge·Worker 현행 소스/배포 설정 스냅샷 및 실제 복원 권한 확인.
2. 후보 SQL 두 파일을 운영의 정확한 테이블/함수 시그니처·권한·RLS와 비교하고, 승인된 신규 SQL만 각각 트랜잭션으로 적용/검증.
3. Edge 두 함수를 해당 SQL과 호환되는 동일 후보 버전으로 교체하고 JWT/권한·다운로드·업로드·범위 경로 점검. 실패 시 변경 중단 및 사전 확보한 호환 버전으로 복구.
4. Cloudflare Worker+정적 자산을 고정 커밋에서 배포한 뒤 부모/학생 권한·PDF·녹음·제출·피드백 점검. 배포 전후에 기존 학생 배정/공개 상태를 변경하지 않음.
5. 실제 Galaxy 실기기 인수검사 후 사용자 확인. 유료 AI는 계속 비활성.

**주의:** 이 순서는 원자적 배포가 아니며 단계별 호환성 구간·장애 위험이 있다. DB 신규 함수/테이블은 코드 롤백만으로 제거되지 않는다. Storage 파일/학생 기록의 삭제·덮어쓰기는 금지. 현재 백업 복원 가능성이 확인되지 않아 **운영 적용 보류**.
