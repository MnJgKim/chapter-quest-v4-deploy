# Chapter Quest V4

목표: 2026년 11월 23일 서우의 첫 학습.

실행 코드는 `app/`, 단일 배포 설정은 루트 `wrangler.jsonc`, 의존성 잠금 파일은 루트 `package-lock.json`에 있습니다. 기존 ZIP과 모든 Git 이력은 보존합니다. `app/public`만 정적 자산으로 배포되며 테스트 자료·계정·서버 백업은 포함되지 않습니다.

루트에서 설치·테스트·빌드합니다. `npm ci`, `npm test`, `npm run build`는 개발자 검증용이며 빌드는 배포를 수행하지 않습니다. 실제 실행은 에이전트가 담당합니다.

[기능·검증 범위](app/README.md) · [무료 학습 자료 준비](app/FREE_LESSON_PREPARATION.md) · [테스트 환경](app/TEST_ENVIRONMENT_PLAN.md)

[Draft PR #1](https://github.com/MnJgKim/chapter-quest-v4-deploy/pull/1)에서 통합 중입니다. 운영 주소는 https://chapter-quest-v4.roscabear.workers.dev/ 입니다. 이 후보의 운영 배포와 운영 데이터 변경은 수행하지 않았으며 별도 사전 승인이 필요합니다. 유료 서비스·브랜치·추가 과금 자원은 생성하지 않습니다.
