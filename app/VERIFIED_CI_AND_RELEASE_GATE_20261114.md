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

## Supabase 보안/성능/상태 Advisor — 운영 읽기 전용 (2026-11-14)
- `get_advisors(type=security|performance|health)` 실행. **health lints 0건**.
- Security `rls_enabled_no_policy` INFO 7건: `child_progress`, `cq_pairing_requests`, `cq_v4_activities`, `cq_v4_approval_requests`, `cq_v4_invites`, `cq_v4_lesson_schedule`, `cq_v4_student_submissions`. 일부는 의도된 서버 함수 전용 테이블일 수 있음. RLS 제거 금지.
- Security `anon_security_definer_function_executable` WARN 9건: 구형 CQ 4건(`cq_approve_pairing`, `cq_create_pairing_request`, `cq_get_my_student`, `cq_is_student`)과 V3D 5건. 네 CQ 함수는 정의를 읽기 전용 확인했으며 관리자 검사, 익명 사용자 검사, `auth.uid()`에 묶인 소유권 조건이 각각 존재. **Advisor 경고만으로 실제 취약점 확정 불가**. V3D 함수는 별도 감사를 마치기 전 변경 금지.
- Security `authenticated_security_definer_function_executable` WARN 36건: V4의 인증된 RPC 다수 포함. 호출자별 소유권·관리자 검사 검토 필요. Supabase 익명 로그인 사용자는 DB `authenticated` 역할이 될 수 있으므로 역할만으로 신뢰하면 안 됨.
- Security `auth_allow_anonymous_sign_ins` WARN 다수 및 `auth_leaked_password_protection` WARN 1건. 익명 로그인 중단 시 기존 학생 연결이 끊길 수 있으므로 사전 데이터/계정 영향 분석과 별도 승인 필수.
- Performance `unindexed_foreign_keys` INFO 15건 (V4·기존 CQ·V3D 혼재). 기능 차단 오류가 아닌 잠재 성능 저하 경고. 기존 DB에 인덱스를 무단 추가하지 않음.
- 참고: <https://supabase.com/docs/guides/database/database-linter?lint=0028_anon_security_definer_function_executable>, <https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy>, <https://supabase.com/docs/guides/database/database-linter?lint=0001_unindexed_foreign_keys>.
- 이번 점검에서 운영 DB/인증/정책/Edge/Storage 변경 **0건**. 보안 권고의 실제 위험도·우선순위는 권한별 호출 시나리오와 V3D 영향 검증 후 확정.

## 신규 SQL 2건의 운영 스키마 사전 호환성 점검 (2026-11-14)
`information_schema.columns` 및 `pg_constraint`에 대한 읽기 전용 조회로 후보 SQL이 참조하는 기존 컬럼과 FK를 점검.

- `cq_v4_parent_lesson(uuid)` 참조 컬럼 확인: `cq_v4_pdf_chapters(chapter_id,parent_user_id)`, `cq_v4_activities(chapter_uuid,questions,vocabulary,writing_prompt,speaking_prompt,published_at,approval_id)`, `cq_v4_approval_requests(id,chapter_uuid,parent_user_id,answer_key)` 모두 운영에 존재.
- `cq_v4_pdf_page_ranges` 참조 대상 확인: `cq_v4_pdf_chapters(chapter_id)` PK, `auth.users(id)` 및 기존 원본 검증 컬럼 `pdf_ready`, `pdf_verified_at`, `storage_path` 존재.
- `cq_v4_commit_pdf_range`에서 새 `cq_v4_pdf_chapters` 행을 넣을 때 요구되는 `chapter_id,parent_user_id,title,storage_path,pdf_ready,pdf_verified_at` 존재. 기존 `cq_v4_storage_path_owner_binding`, `cq_v4_storage_path_valid`, `cq_v4_pdf_chapters_storage_path_key` 제약과 후보 생성 경로 `parent/uuid.pdf` 형식이 정합.
- 기존 함수 `cq_is_admin()`, `cq_v4_register_approval_once(...)`, `cq_v4_bind_verified_pdf(uuid,uuid)` 존재 및 인자 확인.
- **한계**: 운영 DB에 SQL을 적용하지 않았으므로 실제 `CREATE FUNCTION` 컴파일, 트랜잭션 충돌, 실행 시 권한, FK 동작, 전체 Edge 호환성을 보장하지 않음. 운영 승인과 복구 백업 전에는 실행 금지.
- **배포 안전 결정**: 두 SQL은 신규 객체 생성이지만 후속 Edge 호출은 기존 챕터·승인·Storage에 쓰기를 수행할 수 있으므로, 배포 승인과 실제 학습 데이터 게시 승인을 구분한다.

## 11월 23일 실제 첫 학습 데이터 — 집계만 재확인 (2026-11-14)
- 운영 DB 읽기 전용 `COUNT(*)` 조회: `cq_v4_pdf_chapters` **3**, `cq_v4_pdf_assignments` **2**, `cq_v4_lesson_schedule` **2**, `released_at IS NOT NULL` **0**, `cq_v4_student_submissions` **0**.
- 실제 학습 대상은 `FIRST_LESSON_CONFIRMED.md`에 따른 기존 PDF 전체 11쪽. 사용자 확인 내용이며 운영 파일 본문 자체를 내려받아 검증한 것은 아님.
- 기존 배정과 일정이 있다는 사실만으로 **서우 실제 UID가 최종 확인됐다고 판단하지 않음**. 기존 익명 계정/세션과 부모 계정 연결은 실기기 인수검사 대상.
- 모든 수업은 부모의 별도 공개 전까지 비공개. 이번 조회는 원본·배정·일정·공개·제출을 변경하지 않음.
- 운영 Supabase 개발 브랜치 목록: **0개**. 테스트 브랜치가 자동으로 운영 데이터 백업을 제공하지 않음. 독립 백업/복구 검증은 계속 미완료.

## 복구 대상 규모 및 백업 승인 게이트 (2026-11-14)
운영 Supabase에서 COUNT 집계만 조회, 학생 PII/파일 본문/인증 토큰은 읽거나 반출하지 않음:
- `auth.users` **11**, `storage.buckets` **2**, `storage.objects` **4**.
- `cq_v4_pdf_chapters` **3**, `cq_v4_student_submissions` **0**, `v3d_vocab_sessions` **2**.
- 동일 운영 프로젝트에 V4와 기존 V3-D가 공존하므로 **V4만 선택 복원하는 것으로 전체 서비스 안전을 보장할 수 없음**.
- 데이터베이스 스키마+데이터, Auth 사용자 및 세션 영향, Storage 실제 오브젝트 bytes+메타데이터+버킷 정책, Edge 소스+환경설정, Cloudflare Worker 코드+설정+정적 자산을 각각 보호해야 함.
- SQL `COUNT(*)`, GitHub commit, Edge 함수 SHA는 **백업이 아님**. Supabase 브랜치도 0개이며 별도 백업/복원 권한과 실제 복원 테스트는 미확인.
- 복구 가능성 확인 전에는 **운영 SQL/Edge/Worker 변경 금지**. 운영 전체 DB를 과거 시점으로 복원하면 이후 생성된 Auth/학습 데이터가 유실될 수 있어, 배포 실패 시 코드/함수의 버전 롤백과 DB 변경의 호환 유지가 우선이며 데이터 삭제/전체 복원은 별도 승인 필요.
- 민감 자료의 GitHub 커밋/PR 첨부 금지. 복원 테스트는 격리된 환경에서 수행해야 하며 새 Supabase 브랜치/프로젝트의 과금 여부는 별도 확인·승인 전 생성 금지.
