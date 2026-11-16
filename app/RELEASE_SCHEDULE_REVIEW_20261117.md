# 학생별 일정·공개 조건 검토 (2026-11-17 한국 시간)

운영 배포/SQL/Edge/데이터 변경 없음. 기존 학생별 일정 브랜치 11721f8을 바탕으로 최소 프런트 수정. PIN·로그인 수정 브랜치 병합 없음.

## 요구사항과 구현

- 기본 요일: 서우 월·수·목, 서진 화·수·금, 시우 평일(임시). 기기 데모의 부모 설정이며 서버 계정에는 이름을 추측해 적용하지 않는다.
- 서버 계정의 접근 권한은 학생별 실제 lesson_date/배정/게시/공개 승인으로 결정한다. 요일은 접근 제한 조건이 아니다.
- 학생 화면의 고정 월·목 순서 표시를 서버 날짜 표시로 교체. 과거 공개 챕터도 계속 표시한다.
- 기기 데모는 과거 주에 배정한 미제출 챕터를 다음 주에 중복 자동 배정하지 않는다. 설정 외 요일의 기존 배정도 표시한다. 저장 데이터 삭제나 마이그레이션 없음.

## 운영 경로 조사

- 최초 로그인/기존 세션 복구/새로고침 모두 student-api.assignedChapters → cq_v4_my_released_chapters.
- 직접 호출 가능한 cq_v4_my_chapters 및 cq_v4_my_chapter_activities도 cq_v4_is_released를 검사.
- PDF: pdf-transport → cq-v4-pdf-link 운영 v2. 학생 JWT/RLS 배정·PDF·등록 및 명시적 is_released 확인 후 120초 서명 URL 발급.
- cq_v4_submit_answers는 공개 검사 후 배정/게시/답변/녹음을 검증한다. 기존 제출은 ON CONFLICT DO NOTHING으로 보존.
- 녹음 Storage SELECT/INSERT 정책도 공개 조건을 검사. 발급된 PDF 링크는 최대 120초 유효할 수 있고 이미 내려받은 파일은 회수할 수 없다.
- cq_v4_my_submission은 본인의 기존 제출/공개 피드백 조회이며 미래 문제를 제공하지 않는다.
- cq_v4_my_lesson_schedule은 미래 일정의 제목/날짜와 공개 여부를 제공할 수 있으나 문제/PDF 제공 경로는 아니다. 현재 학생 화면은 호출하지 않는다.
- 활동/승인/일정/제출 테이블: RLS 활성, anon/authenticated SELECT 권한 없음. 원본 Storage 직접 조회 정책 없음.
- 공개 함수는 일정+PDF 준비+부모 연결+학생 배정+게시+released_at+학생 시간대의 예정일을 모두 요구한다. 게시 승인은 publish_approved의 승인 원본 일치 검사에서 처리된다.
- 일정 PK는 (student_user_id,chapter_id). 부모가 등록한 절대 날짜이며 주간 반복 생성 로직 없음. 점검 범위에서 미래 콘텐츠 공개 우회 경로를 발견하지 못함. 모든 서비스에 대한 침투 테스트 완료를 의미하지 않음.

## 백업과 보존

- Git 전체 refs bundle: /workspace/work/chapter-quest-before-20261117.bundle. 새로 fetch한 원격 학생별 일정 브랜치도 별도 bundle에 보존.
- 운영 함수/정책/학생 PDF Edge 소스는 /workspace/work/server-*.json 스냅샷. SQL 테스트 fixture는 조회한 운영 함수 정의이며 배포용 migration이 아님.
- 운영 일정 11건 fingerprint 5b235db5e9e614c17c48932b39beefd5, 제출 1건 fingerprint fb0a18d23a53ec2253c7cbfb293a395b. 전후 재확인.
- 이 스냅샷은 전체 DB/Auth/Storage 복원 백업을 대신하지 않는다.
- Cloudflare 공개 자산 사본은 확보. 계정 인증 도구와 연결된 대시보드 탭이 없어 현재 배포 ID/전체 설정/복구 접근은 미확보. 운영 배포 차단.

## 검증과 복구

일정/학생 API 회귀 및 전체 npm test, dry-run build, 격리 브라우저 smoke 실행. 별도 PGlite 검사는 운영 함수 정의를 격리 스키마에 로드하여 미래 목록·직접 활동 차단, 배정/게시/공개/PDF/부모 연결 누락 차단, 과거 공개 유지·중복 없음 등을 검증한다. 운영 계정/실제 Galaxy 테스트와 동일하지 않다. SQL 테스트의 합성 스키마는 운영 RLS 전체 복제가 아니다.

배포 전 반드시 Cloudflare 실제 운영 버전 ID, 설정·바인딩·라우트·사용자 지정 도메인과 롤백 접근을 확보하고 사용자 승인을 받는다. 실패하면 캡처한 직전 Worker 버전으로 트래픽 복구하고 화면/API를 재확인한다. 학생 localStorage/IndexedDB, Auth/Storage/DB 행은 지우지 않는다. 이번 후보는 DB/Edge 변경이 없어 DB 복원은 필요하지 않다. 현재 GitHub main은 업로드 ZIP만 있어 main 전체 배포나 후보 브랜치 전체 배포를 하면 안 된다. 운영 소스/설정 대비 프런트 차이만 검토하여 배포해야 한다.
