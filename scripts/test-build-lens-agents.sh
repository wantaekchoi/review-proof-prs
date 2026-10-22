#!/usr/bin/env bash
# build-lens-agents.sh 자가검사. 스킬 저장소 루트에서 돌린다.
set -u
cd "$(dirname "$0")/.."
fail=0
scripts/build-lens-agents.sh >/dev/null || { echo "생성 실패"; exit 1; }
n=$(ls agents/lens-*.md 2>/dev/null | wc -l | tr -d ' ')
[ "$n" = 11 ] || { echo "정의 수 $n ≠ 11"; fail=1; }
for f in agents/lens-*.md; do
  python3 - "$f" <<'PY' || fail=1
import sys, re
t = open(sys.argv[1], encoding='utf-8').read()
head = t.split('---')[1]
need = ['name', 'description', 'model', 'effort', 'disallowedTools']
f = dict(re.findall(r'^(\w+):\s*(.+)$', head, re.M))
miss = [k for k in need if not f.get(k)]
if miss: sys.exit(f'{sys.argv[1]}: 빠진 키 {miss}')
d = f['description']
if not (d.startswith('"') and d.endswith('"')) or '"' in d[1:-1]: sys.exit(f'{sys.argv[1]}: description 인용 깨짐')
if 'Write' not in f['disallowedTools'] or 'Edit' not in f['disallowedTools']: sys.exit(f'{sys.argv[1]}: 쓰기 도구가 안 막혔다')
PY
done
# 모델이 렌즈 파일과 같은가 (0·10 opus, 2 sonnet 표본)
grep -q '^model: opus' agents/lens-0.md || { echo "lens-0 모델"; fail=1; }
grep -q '^model: sonnet' agents/lens-2.md || { echo "lens-2 모델"; fail=1; }
f2=skills/review-proof-prs/lenses/2-correctness.md; b2=$(mktemp); cp "$f2" "$b2"
f3=skills/review-proof-prs/lenses/3-edge.md; b3=$(mktemp); cp "$f3" "$b3"
restore() { cp "$b2" "$f2"; cp "$b3" "$f3"; rm -f "$b2" "$b3"; scripts/build-lens-agents.sh >/dev/null; }
trap restore EXIT
# 렌즈 파일 한 줄 수정 → --check 실패해야
echo "- 시험 줄" >> "$f2"
scripts/build-lens-agents.sh --check >/dev/null 2>&1 && { echo "--check 가 낡은 정의를 못 잡았다"; fail=1; }
cp "$b2" "$f2"
scripts/build-lens-agents.sh --check >/dev/null || { echo "--check 가 최신을 거부"; fail=1; }
# 백슬래시가 든 임무 문구도 YAML 에서 그대로 읽혀야 한다
sed 's/\*\*임무: /**임무: C:\\temp /' "$b3" > "$f3.tmp" && mv "$f3.tmp" "$f3"
scripts/build-lens-agents.sh >/dev/null
d=$(ruby -ryaml -e 'puts YAML.load(File.read("agents/lens-3.md").split("---")[1])["description"]')
case "$d" in *'C:\temp'*) ;; *) echo "백슬래시가 YAML 에서 깨졌다: $d"; fail=1;; esac
cp "$b3" "$f3"
scripts/build-lens-agents.sh >/dev/null
# --check 는 임시 디렉터리를 남기지 않는다
td=$(mktemp -d); TMPDIR=$td scripts/build-lens-agents.sh --check >/dev/null
[ -z "$(ls -A "$td")" ] || { echo "--check 가 임시 디렉터리를 남겼다"; fail=1; }
rm -rf "$td"
# 렌즈 파일이 사라지면 재생성이 그 정의도 지운다
touch agents/lens-99.md; scripts/build-lens-agents.sh >/dev/null
[ ! -e agents/lens-99.md ] || { echo "사라진 렌즈의 정의가 남았다"; rm -f agents/lens-99.md; fail=1; }
[ $fail = 0 ] && echo "통과"
exit $fail
