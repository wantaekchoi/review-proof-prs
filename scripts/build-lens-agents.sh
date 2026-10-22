#!/usr/bin/env bash
# lenses/<N>-*.md + _guardrails.md → agents/lens-<N>.md. 정본은 lenses/ 이고 이건 생성물이다.
#   build-lens-agents.sh          # 생성
#   build-lens-agents.sh --check  # 커밋본과 다르면 실패
set -eu
cd "$(dirname "$0")/.."
L=skills/review-proof-prs/lenses
out=agents
if [ "${1:-}" = --check ]; then
  out=$(mktemp -d "${TMPDIR:-/tmp}/lens-agents.XXXXXX"); trap 'rm -rf "$out"' EXIT
else
  mkdir -p "$out"; rm -f "$out"/lens-*.md   # 사라진 렌즈의 정의도 같이 지운다
fi
python3 - "$L" "$out" <<'PY'
import sys, re, glob, os
L, out = sys.argv[1:]
guard = open(f'{L}/_guardrails.md', encoding='utf-8').read().strip()
for p in sorted(glob.glob(f'{L}/[0-9]*.md')):
    t = open(p, encoding='utf-8').read()
    parts = t.split('---', 2)
    if len(parts) < 3: sys.exit(f'{p}: frontmatter 없음')
    f = dict(re.findall(r'^(\w+):\s*(.+)$', parts[1], re.M))
    for k in ('id', 'name', 'model', 'effort'):
        if not f.get(k): sys.exit(f'{p}: frontmatter {k} 없음')
    m = re.search(r'\*\*임무:\s*(.+?)\*\*', parts[2])
    if not m: sys.exit(f'{p}: **임무:** 줄 없음')
    desc = f"렌즈 {f['id']} {f['name']} — {m.group(1)}".replace('\\', '\\\\').replace('"', "'")
    md = (f"---\nname: lens-{f['id']}\ndescription: \"{desc}\"\n"
          f"model: {f['model']}\neffort: {f['effort']}\n"
          f"disallowedTools: Write, Edit, NotebookEdit\n---\n"
          f"<!-- 생성물: scripts/build-lens-agents.sh 가 {os.path.basename(p)} 와 _guardrails.md 로 만든다. 손으로 고치지 마라. -->\n\n"
          f"너는 review-proof-prs 의 **렌즈 {f['id']} — {f['name']}** 이다. read-only 리뷰어다. "
          f"대상·레벨·맥락은 호출 프롬프트가 준다.\n\n{guard}\n\n{parts[2].strip()}\n")
    open(f"{out}/lens-{f['id']}.md", 'w', encoding='utf-8').write(md)
PY
if [ "${1:-}" = --check ]; then
  if ! diff -r agents "$out" >/dev/null; then
    echo "agents/ 가 lenses/ 와 다르다 — scripts/build-lens-agents.sh 를 돌려라"; diff -r agents "$out" | head -5; exit 1
  fi
  echo "agents/ 최신"
fi
