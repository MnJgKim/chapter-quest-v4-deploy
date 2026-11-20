# Physical phone / Galaxy tablet acceptance — not yet executed

Automated Chromium covers touch, radio selection, inputs, sticky submit controls, parent results, portrait/landscape viewports (360×800, 412×915, 800×1280, 1280×800), PDF rendering and synthetic microphone audio. Viewport emulation does not verify Samsung Internet/Android audio codecs, the hardware microphone, device memory or background suspension.

Use an isolated authorized test account/environment, not an existing student's operating records. Preserve any existing anonymous browser session; do not clear browser data, log out, or convert that user to test recovery.

1. Record real device model, Android/browser version and orientation. Open the actual large PDF as parent; check load time, memory, title/page count/outline when present, zoom and page jump. Distinguish printed page numbers from file-page numbers.
2. Start with empty bounds, navigate to real Chapter 1, choose start/end from the visible page, preview both ends and explicitly confirm. Check no outside pages appear. Cancel/reload must preserve the whole original and existing TXT. Publishing stays blocked until a verified derived PDF is selected.
3. As assigned student, check words, touch choices, inference, keyboard/essay editing, rotating the screen and always reachable submit controls. Confirm only the assigned range opens, including the new-tab link.
4. Check microphone allow/deny, stop, playback audibility, actual device codec, interrupted recording (call, lock, background), durable-save retry and reload. Never clear data while an unsaved recording exists.
5. Complete final submission once, reopen/re-login with a dedicated recoverable test account, verify immutable answers and feedback hidden until parent release. Parent must play audible audio and see the right answers.
6. Repeat with a second assigned student: different drafts, recordings, submissions and feedback; neither can read the other's private audio. Verify revoked/unassigned access is refused.

No physical device results are claimed. Production testing that writes data or requires deployment must wait for explicit approval.

## 운영 서버에서만 남는 검증 (미실행)

- 별도 승인된 후보 배포 후 실제 부모 JWT/관리자·원본 소유권으로 29.3MB 파일 미리보기, 실제 내부 제목/페이지 수/목차와 스캔 여부 확인.
- 부모가 확정한 Chapter 1 범위의 서버 추출 CPU/메모리/시간이 기존 무료 Edge 제한에 맞는지 확인. 합성 소형 PDF 통과로 대용량 성공을 보장하지 않음.
- 실제 익명 UID와 부모 연결의 동일성·기존 기기 세션·필요한 최소 갱신을 승인 범위에서 확인. 계정 대체/이메일 전환은 자동 실행하지 않음.
- 승인한 운영 자료·문항·배정으로 다운로드 제한과 실제 제출/피드백 확인. 이 단계는 운영 쓰기이므로 별도 사전 승인 필요.
- 실제 AI 무료 사용 가능 모델/응답 품질·한도, 실제 Cloudflare 계정 플랜/CPU/배포 버전 확인. 인증 재요청 없이 확인할 수 없는 항목은 미검증 유지.
