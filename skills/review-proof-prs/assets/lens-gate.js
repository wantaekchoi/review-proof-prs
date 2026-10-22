export const meta = {
  name: 'lens-gate',
  description: '카드 N장에 레벨별 렌즈를 병렬로 걸어 판정을 받는다 (1라운드·델타 공용)',
  phases: [{ title: 'Lens', detail: '카드 × 렌즈 read-only 리뷰어를 동시에' }],
}

// ─────────────────────────────────────────────────────────────────────────────
// 렌즈 프롬프트는 이 파일에 없다. 각 에이전트가 자기 렌즈 파일을 직접 읽는다 —
// 워크플로 스크립트는 파일시스템에 접근할 수 없고, 프롬프트를 여기 복사하면
// lenses/ 와 두 벌이 되어 반드시 갈린다.
//
// args = {
//   skill_dir : review-proof-prs 스킬 경로 (lenses/ 의 부모)
//   ws        : 워크스페이스 경로 (본문·증거·판정문이 사는 곳)
//   levels    : { light: [0,2,6], essential: [...], ... }  ← lens-levels.json 에서 뽑아 넘긴다
//   lens_meta : { "0": {model, effort, name}, ... }        ← lenses/*.md frontmatter 에서 뽑아 넘긴다
//   use_agents: true 면 agentType <agent_prefix><N> 으로 부른다(가드레일·각도가 정의에 박혀 있음). lens-args.sh 가 정한다.
//   agent_prefix: 'lens-' 또는 플러그인 설치본 'review-proof-prs:lens-' (생략 시 'lens-')
//   cards     : [{ key, repo, wt, level, gist,
//                  body?, evidence_dir?,      // 기본값 <ws>/pr-bodies/<key>.md, <ws>/evidence/<key>
//                  changes? }]                // 있으면 델타 라운드
// }
// ─────────────────────────────────────────────────────────────────────────────

const SCHEMA = {
  type: 'object',
  properties: {
    lens: { type: 'string', description: '렌즈 번호와 이름. 예: "0 전제 파괴"' },
    body_sha: { type: 'string', description: 'shasum -a 256 을 직접 돌려 얻은 본문 해시' },
    verdict: { type: 'string', enum: ['SUBMIT-OK', 'FIX-FIRST', 'BLOCK'] },
    evidence: { type: 'string', description: '판정 근거 — 실제로 돌린 명령과 그 출력' },
    concerns: { type: 'array', items: { type: 'string' }, description: '반영해야 제출 가능한 지적. 없으면 빈 배열' },
    nits: { type: 'array', items: { type: 'string' }, description: '차단하지 않는 지적' },
  },
  required: ['lens', 'body_sha', 'verdict', 'evidence', 'concerns', 'nits'],
}

const A = args
const SKILL = A.skill_dir
const WS = A.ws
const LEVELS = A.levels
const META = A.lens_meta
const AGENTS = A.use_agents === true
const PREFIX = A.agent_prefix || 'lens-'

function prompt(card, id) {
  const m = META[String(id)] || {}
  const body = card.body || `${WS}/pr-bodies/${card.key}.md`
  const evi = card.evidence_dir || `${WS}/evidence/${card.key}`
  const delta = card.changes_file || (card.changes && card.changes.length)

  const lines = [
    `당신은 **렌즈 ${id} ${m.name || ''}** 입니다. read-only 리뷰어입니다.`,
    '',
    ...(AGENTS
      ? (delta ? ['## 먼저 읽어라', '', `\`${SKILL}/lenses/_delta.md\` — 델타 라운드 규칙`, ''] : [])
      : ['## 먼저 읽어라 (이 셋이 당신의 규칙이다)', '',
         `1. \`${SKILL}/lenses/_guardrails.md\` — 공통 가드레일`,
         `2. \`${SKILL}/lenses/${id}-*.md\` — **당신의 렌즈 각도.** 이 파일이 당신이 볼 것을 정한다.`,
         delta ? `3. \`${SKILL}/lenses/_delta.md\` — 델타 라운드 규칙` : null, '']),
    '## 대상',
    '',
    `- PR 본문: \`${body}\``,
    `- 증거 디렉터리: \`${evi}/\` — 안의 파일을 직접 읽어라`,
    `- 워크트리(읽기 전용): \`${card.wt}\` — 기준선 \`origin/${card.base || 'main'}\`, 내 커밋 \`HEAD\``,
    `- 업스트림 저장소: ${card.repo}`,
    `- 스킬 경로: \`${SKILL}\``,
    `- 렌즈 레벨: ${card.level}`,
    '',
    `카드 요지: ${card.gist}`,
  ].filter(x => x !== null)

  if (delta) {
    lines.push('', '## 이번 라운드에 바뀐 것 (이것만 본다)', '')
    if (card.changes_file) lines.push(`\`${card.changes_file}\` 를 읽어라. 바뀐 것이 한 줄씩 들어 있다.`)
    else card.changes.forEach((c, i) => lines.push(`${i + 1}. ${c}`))
    lines.push('', '각각에 대해 (a) 닫혔는가 (b) 새 거짓이 들어왔는가 둘만 판정하라. 하나당 5분.')
  }

  return lines.join('\n')
}

const CARDS = A.cards
const jobs = []
for (const c of CARDS) for (const id of LEVELS[c.level]) jobs.push({ card: c, id })

phase('Lens')
log(`카드 ${CARDS.length}장 · 렌즈 ${jobs.length}개 병렬${CARDS.some(c => c.changes || c.changes_file) ? ' (델타)' : ''}${AGENTS ? ' · 에이전트 정의' : ' · 렌즈 파일 직접'}`)

const results = await parallel(jobs.map(j => () => {
  const m = META[String(j.id)] || {}
  const opts = { label: `${j.card.key}·L${j.id}${(j.card.changes || j.card.changes_file) ? 'δ' : ''}`, phase: 'Lens', schema: SCHEMA }
  if (AGENTS) opts.agentType = `${PREFIX}${j.id}`     // 모델·effort 는 정의가 정한다
  else { opts.model = m.model; opts.effort = m.effort }
  return agent(prompt(j.card, j.id), opts).then(r => r && Object.assign({}, r, { card: j.card.key, lensId: j.id }))
}))

const ok = results.filter(Boolean)
const missing = results.length - ok.length
if (missing > 0) log(`경고: ${missing}개가 결과 없이 끝났다 — 그 렌즈는 안 돈 것으로 친다`)

// 집계는 다수결이 아니다. 하나라도 막으면 막힌다.
const summary = CARDS.map(c => {
  const mine = ok.filter(r => r.card === c.key)
  const want = LEVELS[c.level].length
  const bad = mine.filter(r => r.verdict !== 'SUBMIT-OK')
  // 렌즈가 해시를 몇 글자 잘라 적는 일이 있다. 48자 이상 접두 일치는 같은 본문으로 친다.
  const full = mine.map(r => r.body_sha).filter(x => x && x.length === 64)
  const canon = full.length ? full.sort()[Math.floor(full.length / 2)] : null
  const same = x => x === canon || (canon && x && x.length >= 48 && canon.startsWith(x))
  const shortSha = mine.filter(r => r.body_sha !== canon && same(r.body_sha))
  if (shortSha.length) log(`  ${c.key}: 해시를 자른 렌즈 ${shortSha.map(r => `L${r.lensId}(${r.body_sha.length}자)`).join(' ')} — 접두 일치라 같은 본문으로 친다`)
  const shas = [...new Set(mine.map(r => (same(r.body_sha) ? canon : r.body_sha)))]
  // 본문 해시가 16진수가 아니면 본문과 판정이 묶였다는 증거가 없다.
  const hexSha = shas.length === 1 && /^[0-9a-f]{48,64}$/.test(shas[0] || '')
  if (shas.length === 1 && !hexSha) log(`  ${c.key}: ⚠ body_sha 가 16진 해시가 아니다 (${String(shas[0]).slice(0, 40)}…) — 통과시키지 않는다`)
  const pass = mine.length === want && bad.length === 0 && shas.length === 1 && hexSha
  log(`${c.key}: ${mine.length}/${want} · ${bad.length ? bad.map(b => `L${b.lensId}=${b.verdict}`).join(' ') : '전원 SUBMIT-OK'}${shas.length > 1 ? ` · ⚠ body_sha 갈림 ${shas.length}종` : ''}`)
  return { key: c.key, level: c.level, pass, got: mine.length, want, blocked: bad.map(b => b.lensId), sha_split: shas.length > 1, body_sha: shas[0] }
})

return { results: ok, summary, missing }
