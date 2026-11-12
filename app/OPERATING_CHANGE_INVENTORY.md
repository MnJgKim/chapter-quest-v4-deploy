# 運用適用候補 / 운영 적용 후보 파일

운영 적용 승인이 아닌 검토 목록이다. 적용할 때는 이 목록과 대상 커밋을 함께 확인한다.

| 파일 | 변경 및 영향 |
|---|---|
| `wrangler.jsonc` | Worker/Assets/AI 바인딩·공개 프로젝트 설정. AI 무료 확인 플래그는 false 유지. 비밀키를 자산에 넣지 않는다. |
| `app/worker.mjs` | 부모 Auth/관리자 권한 검사, 입력 제한과 AI 응답 처리. 초3 공통 구성인 단어6·내용이해3·추론2·글쓰기1·말하기1을 생성 요청에 적용한다. 실제 생성 결과는 부모 검토가 필요하다. |
| `app/public/index.html`, `app/public/_headers`, `app/public/boot-health.js` | 웹앱 진입·보안 헤더·기동 확인. |
| `app/public/js/*.js`, `app/public/*.js` | 부모 검토·승인·게시/배정 UI, 원본/범위 미리보기·재사용, 학생 세션 확인·학습·임시 저장·녹음·제출·피드백. 실제 정적 파일 전체 목록은 아래 명령으로 확인한다. |
| `app/build-assets.mjs` → `app/public/vendor/*` | 고정 버전 PDF.js/pdf-lib와 라이선스 복사. 원본 PDF·전사본·정답 파일을 배포하지 않는다. |
| `app/local-supabase/supabase/migrations/20261111013217_cq_parent_lesson_context.sql` | 새 부모 전용 읽기 함수 `cq_v4_parent_lesson(uuid)`, EXECUTE 권한 부여. 기존 함수 교체 없음. |
| `app/local-supabase/supabase/migrations/20261111233341_cq_verified_pdf_ranges.sql` | 새 `cq_v4_pdf_page_ranges` 테이블/인덱스/RLS 및 `cq_v4_commit_pdf_range`, `cq_v4_register_range_approval_once` 함수. 생성 시 기존 데이터 DML 없음. 이후 호출하면 범위/새 챕터 또는 승인 자료를 기록하므로 별도 쓰기 승인 필요. |
| `app/local-supabase/supabase/functions/cq-v4-pdf-parent/index.ts` | 소유 부모만 원본/녹음 접근, 범위 검증·재사용, 승인된 게시 자료만 배정. 기존 create/upload/finalize/assign/unassign도 쓰기 기능이며 조회 승인으로 실행하지 않는다. |
| `app/local-supabase/supabase/functions/cq-v4-pdf-link/index.ts` | 현재 학생 연결·배정·게시·범위/파일 해시 검사 후 짧은 서명 URL 반환. |
| `app/local-supabase/supabase/functions/_shared/pdf-range.ts` | 페이지 수/범위/해시 검증. 전체 범위는 원본 바이트 그대로 반환, 부분 범위는 별도 파일 생성. |

웹앱 정적 파일의 정확한 빌드 목록은 `node app/build-assets.mjs` 후 `app/public/` 파일 목록과 SHA-256으로 고정한다. 서버 정의/Edge와 프런트의 버전 호환성을 먼저 확인한다.

## SQL 검증 범위

마이그레이션 자체는 새 객체 CREATE와 새 객체의 권한 설정만 수행한다. 함수 본문의 INSERT는 설치 시 실행되지 않는다. DELETE/UPDATE/TRUNCATE/DROP 및 기존 함수 CREATE OR REPLACE는 없다. 같은 마이그레이션 재실행은 이름 충돌로 실패하므로 자동 재적용하지 않는다. 각각 명시적 트랜잭션으로 적용하고 실패 시 ROLLBACK한다. 스키마 도구 일괄 push 대신 승인된 두 파일만 검토한다.

격리 합성 DB에서 기존 사용자·연결·챕터·배정·문제·제출·공개 피드백·Storage 메타데이터를 먼저 넣고 두 SQL을 적용해 모든 기존 테이블 행과 기존 함수 정의가 같은지 확인한다. 이는 운영에 SQL을 적용한 검증이 아니며 실제 운영 권한·동시 변경·락 영향까지 보장하지 않는다. 새 FK는 향후 참조된 사용자/챕터 삭제를 제한할 수 있다.

## 제외

로컬 bootstrap `20261111000933_cq_local_schema.sql`, 테스트·fixtures·lean 환경, 역사적 `app/server-review/candidate/` 및 rollback SQL, 실제 원문·문제/정답·개인 계정 기록은 운영 일괄 적용/공개 배포 대상이 아니다. 계정 생성/삭제/전환, PDF 교체, 자료 등록/게시/배정 및 실제 학습 쓰기는 코드 적용 승인에 자동 포함되지 않는다.

## 복구 원칙

적용 전 현재 Worker 버전/설정과 Edge 소스/JWT, 변경 대상 SQL 정의/권한을 비공개로 보관하고 실제 복구 접근을 확인한다. DB/Storage 전체 백업이 없으면 있다고 표시하지 않는다. 실패한 SQL 트랜잭션은 롤백한다. 커밋 후에는 새 데이터를 삭제하지 말고 호환성을 확인한 코드/설정을 복원한다. 과거 버전의 범위 보안 약화와 manifest 비호환을 평가한다. 이미 발급한 URL의 즉시 무효화나 이미 쓴 제출/녹음 취소를 코드 복구로 보장하지 않는다. 실기기 저장소를 지우지 않는다.
