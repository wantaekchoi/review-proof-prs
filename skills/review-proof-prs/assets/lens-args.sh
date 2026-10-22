#!/usr/bin/env bash
# 렌즈 게이트 워크플로 args 의 고정 부분(levels·lens_meta·skill_dir)을 lens-levels.json·lenses/ 실물에서 뽑는다.
# 워크플로 스크립트는 파일시스템을 못 읽어서 이 값을 args 로 넣어야 한다.
#
#   FIXED=$(.../assets/lens-args.sh "$PWD")
#   CARDS='[{"key":"...","repo":"...","wt":"...","level":"light","gist":"..."}]'
#   python3 -c 'import json,sys; a=json.loads(sys.argv[1]); a["cards"]=json.loads(sys.argv[2]); print(json.dumps(a,ensure_ascii=False))' "$FIXED" "$CARDS"
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"   # skills/review-proof-prs
ws="${1:-$PWD}"

[ -f "$here/references/lens-levels.json" ] || { echo "거부: lens-levels.json 이 없다 → $here" >&2; exit 2; }
[ -d "$here/lenses" ] || { echo "거부: lenses/ 가 없다 → $here" >&2; exit 2; }

SKILL="$here" WS="$ws" python3 - <<'PY'
import json, os, re, glob

skill = os.environ['SKILL']

levels = {k: v['required'] for k, v in
          json.load(open(f'{skill}/references/lens-levels.json'))['levels'].items()
          if v.get('required')}

meta = {}
for p in sorted(glob.glob(f'{skill}/lenses/[0-9]*.md')):
    head = open(p, encoding='utf-8').read().split('---')[1]
    f = dict(re.findall(r'^(\w+):\s*(.+)$', head, re.M))
    meta[f['id']] = {'name': f['name'], 'model': f.get('model', 'sonnet'),
                     'effort': f.get('effort', 'medium')}

missing = sorted({str(i) for ids in levels.values() for i in ids} - set(meta))
if missing:
    raise SystemExit(f'거부: 레벨이 요구하는 렌즈 파일이 없다 → {missing}')

# 에이전트 정의 lens-<N> 이 전부 있을 때만 쓴다. 일부만 있으면 모델이 섞인다.
# 순서: LENS_AGENT_PREFIX → ~/.claude/agents → 플러그인 캐시(<플러그인>:lens-<N>).
def complete(d): return all(os.path.exists(f'{d}/lens-{i}.md') for i in meta)
root = os.path.dirname(os.path.dirname(skill))   # 플러그인 루트: <cache>/<마켓>/<플러그인>/<버전>
prefix = os.environ.get('LENS_AGENT_PREFIX')
if prefix is None:
    if complete(os.path.expanduser('~/.claude/agents')):
        prefix = 'lens-'
    elif '/.claude/plugins/cache/' in root + '/' and complete(f'{root}/agents'):
        prefix = os.path.basename(os.path.dirname(root)) + ':lens-'
    else:
        prefix = ''

print(json.dumps({'skill_dir': skill, 'ws': os.environ['WS'],
                  'levels': levels, 'lens_meta': meta,
                  'use_agents': bool(prefix), 'agent_prefix': prefix}, ensure_ascii=False))
PY
