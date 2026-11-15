# 추가 비용 없이 학습 자료 준비하기

부모 화면에서 원본 PDF와 AI용 텍스트를 준비한 뒤 다음 중 하나를 사용합니다.

- ‘문제 직접 추가’로 문제와 부모용 모범 답안을 작성합니다. 독후감·말하기 질문도 저장한 뒤 현재 문제를 승인합니다.
- ‘AI 초안 JSON 가져오기’로 아래 형식의 파일을 가져옵니다. 원문에 맞는 문제·정답·단어·활동인지 검토한 뒤 승인합니다. 가져오기만으로 학생에게 게시되지는 않습니다.

```json
{
  "questions": [
    {"kind":"mc","text":"Question in English","options":["Option A","Option B"],"correct":0},
    {"kind":"inference","text":"Inference question","sample":"Parent model answer"}
  ],
  "vocabulary":[{"word":"word","meaning":"한국어 뜻","example":"English example."}],
  "writingPrompt":"Reading journal question",
  "speakingPrompt":"Speaking question"
}
```

객관식 정답 번호는 0부터 시작합니다. 서술형에는 `sample`이 필요합니다. 승인 후에는 검증된 서버 PDF와 게시 대상 학생을 선택하여 별도로 게시합니다. 서버 게시·배정은 실제 학생 데이터 변경이므로 현재 작업에서 자동 실행하지 않습니다.

현재 ChatGPT 대화에서 원문을 바탕으로 같은 형식의 초안을 작성하거나 직접 작성할 수 있습니다. JSON 가져오기와 수동 작성은 외부 AI API를 호출하지 않습니다. 원본 PDF와 브라우저 백업 파일은 별도로 보관하세요.
