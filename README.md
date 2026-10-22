# review-proof-prs

업스트림 오픈소스 저장소에 PR 을 내기 전에 거치는 검증 게이트다. 그럴듯하지만 틀린 PR(재현되지 않는 버그, 증상만 덮는 수정, 실물과 다른 본문)이 나가는 것을 막는다. Claude Code 플러그인(스킬 1개 + 렌즈 에이전트 11개 + 게이트 스크립트)으로 배포한다.

```
재현 RED/GREEN → 레벨별 필수 렌즈 독립 검증 → 본문 게이트 → 제출(사람 승인)
```

1. **재현** — 미수정 코드에서 실패(RED), 최소 수정 후 해소(GREEN)를 실제 출력으로 남긴다. 재현이 안 되면 거기서 버린다.
2. **렌즈** — 서로 다른 각도의 read-only 서브에이전트가 diff·증거·본문을 병렬로 검사한다. 에이전트 정의로 돌 때는 쓰기 도구가 막혀 있다. 집계는 다수결이 아니라 하나라도 막으면 막힌다. 몇 개를 돌릴지는 레벨이 정한다(`premise` 1개 · `claim` 2개 · `light` 3개 · `essential` 5개 · `full` 11개 + 반박자 3인). 렌즈 0 은 어느 레벨에서도 빠지지 않는다.
3. **본문 게이트** — `scripts/lens-record.sh` 는 렌즈가 직접 잰 본문 해시와 레벨의 필수 렌즈를 대조해 영수증을 남긴다. `scripts/outbound-check.sh` 는 본문에서 사실 주장 후보를 뽑아 근거 줄 수가 모자라면 거부하고, 근거에 추론 표현이 있으면 거부하며, 본문 해시와 맞는 렌즈 영수증이 있어야 통과시킨다. 본문을 한 글자라도 고치면 렌즈를 다시 돌려야 한다.
4. **제출** — push·PR 은 사람이 승인한 뒤에만 한다.

## 렌즈

| # | 이름 | 보는 것 |
|---|---|---|
| 0 | 전제 파괴 | 이 발견이 참이려면 무엇이 참이어야 하는지 열거하고 실측으로 깬다 |
| 1 | 회의론/의도 | 메인테이너가 "의도된 동작" 으로 닫을 여지 |
| 2 | 정확성 | root cause 를 고치는지, 증상만 덮는지 |
| 3 | 엣지 | 경계·널·빈값·최대치·0 |
| 4 | 부작용 | 다른 경로·형제 기능·기존 테스트 |
| 5 | 메커니즘/E2E | 재현이 실제 사용자 경로인지 |
| 6 | 검증 | RED/GREEN 이 진짜 증명인지, hollow test 인지 |
| 7 | 컨벤션 | 코드·프로젝트 관례 |
| 8 | 수용성 | 범위·정책상 받을지 |
| 9 | 완결성 | 놓친 형제 결함·미검증 주장 |
| 10 | 본문 | 본문의 모든 사실 주장을 실측과 대조 |

정의는 `skills/review-proof-prs/lenses/` 에 있고, `agents/lens-<N>.md` 는 `scripts/build-lens-agents.sh` 로 생성한다.

## 설치

```
/plugin marketplace add wantaekchoi/review-proof-prs
/plugin install review-proof-prs@wantaekchoi
```

플러그인으로 설치하면 렌즈는 `review-proof-prs:lens-<N>` 에이전트로 돈다. `~/.claude/agents/lens-<N>.md` 가 11개 다 있으면 그쪽을 먼저 쓰고, `LENS_AGENT_PREFIX` 로 이름 앞부분을 직접 정할 수도 있다.

부르는 예:

```
이 브랜치의 수정을 review-proof-prs 로 검증해줘. 본문은 pr-bodies/fix-null.md, 레벨은 essential.
```

## 필요한 것

- `jq`, `python3`, `shasum`, `gh`, Claude Code 의 Workflow 기능(`assets/lens-gate.js` 를 돌린다)
- 테스트에만: `ruby`
- 선택: `humanizer` 스킬(영어 본문), `humanize-korean`(한글 본문)

스크립트는 영수증을 `~/.claude/lens-verdicts/` 와 `~/.claude/outbound-receipts/` 에 쓴다.

## English

review-proof-prs is a Claude Code plugin that gates an upstream open-source pull request before it is filed, so that a plausible but wrong PR does not go out. A candidate must first be reproduced (RED on the unpatched code, GREEN after a minimal fix, both with real output). Then independent read-only lens agents review the diff, the evidence and the PR body in parallel; the level decides which lenses are required, lens 0 (premise) is always one of them, and any single block stops the PR. `scripts/lens-record.sh` binds the lens verdicts to a hash of the final body. `scripts/outbound-check.sh` extracts candidate claims from the body, refuses it when there are fewer evidence lines than claims or when the evidence contains guesswork, and requires a lens receipt matching the body hash. Pushing and opening the PR stay with a human.

## License

MIT
