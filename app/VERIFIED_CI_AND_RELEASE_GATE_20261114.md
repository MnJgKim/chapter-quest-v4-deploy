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
