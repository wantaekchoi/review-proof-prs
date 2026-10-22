#!/usr/bin/env bash
# 렌즈 게이트 영수증을 남긴다. outbound-check.sh 는 이것 없이 PR·이슈 본문을 통과시키지 않는다.
#
#   lens-record.sh [--level premise|claim|light|essential|full] <본문.md> <렌즈판정.md>
#
# 영수증은 **본문 내용 해시로** 남는다. 그래서 구조적으로:
#  - 본문이 없으면 영수증을 못 만든다 → "본문 전에 렌즈" 가 불가능해진다
#  - 본문을 한 글자만 고쳐도 영수증이 죽는다 → 고친 뒤 렌즈를 다시 돌려야 한다
#
# 판정파일 요건:
#   BODY-SHA: <sha256>        (렌즈가 **자기가 읽은 본문**에서 직접 잰 해시)
#   VERDICT: SUBMIT-OK        (한 줄. FIX-FIRST·BLOCK 이면 거부)
#   LENS: <번호|렌즈이름> <판정>  (서로 다른 렌즈. 몇 개를 어느 것으로 채우는지는 레벨이 정한다)
#   LEVEL: <premise|claim|light|essential|full> (렌즈가 자기 판정문에 적는다. 없으면 legacy)
#   REFUTE: <반박자id> refuted=<true|false>  (full 에서만)
#
# 레벨 정의는 스킬의 references/lens-levels.json 이 갖는다. 이 스크립트는 정족수를 모른다.
set -u
J="${LENS_LEVELS:-$(cd "$(dirname "$0")/.." && pwd)/skills/review-proof-prs/references/lens-levels.json}"
cli_level=""
case "${1:-}" in
  --level)   cli_level="${2:-}"; shift 2 ;;
  --level=*) cli_level="${1#--level=}"; shift ;;
esac
body="${1:-}"; verdict="${2:-}"
case "${3:-}" in --level*) echo "거부: --level 은 본문 앞에 온다."; exit 2 ;; esac
[ -f "$body" ] && [ -f "$verdict" ] || { echo "usage: $0 [--level premise|claim|light|essential|full] <본문.md> <렌즈판정.md>"; exit 2; }
[ -f "$J" ] || { echo "거부: 레벨 정의가 없다 → $J"; echo "  LENS_LEVELS=<경로> 로 지정해라."; exit 2; }

fail=0
grep -qE '^VERDICT:[[:space:]]*SUBMIT-OK[[:space:]]*$' "$verdict" || {
  echo "거부: '$verdict' 에 'VERDICT: SUBMIT-OK' 줄이 없다."
  echo "  전원 SUBMIT-OK 이어야 제출한다. CONCERN 이 남았으면 반영부터."
  fail=1
}
# 렌즈가 직접 잰 해시를 받아야 낡은 본문을 읽은 렌즈가 잡힌다.
now=$(shasum -a 256 "$body" | cut -d' ' -f1)
seen=$(grep -m1 -E '^BODY-SHA:' "$verdict" | awk '{print $2}')
if [ -z "$seen" ]; then
  echo "거부: 판정에 'BODY-SHA: <sha256>' 줄이 없다."
  echo "  렌즈가 자기가 읽은 본문에서 직접 잰 해시여야 한다(shasum -a 256 <본문>)."
  fail=1
elif [ "$seen" != "$now" ]; then
  echo "거부: 렌즈가 읽은 본문과 지금 본문이 다르다."
  echo "  렌즈가 본 것: $seen"
  echo "  지금 본문   : $now"
  echo "  본문이 렌즈 뒤에 바뀌었다. 렌즈를 다시 돌려라."
  fail=1
fi
# 레벨을 정한다 — 판정문의 LEVEL: 이 정본이고 --level 은 대조용이다.
lvl=$(grep -m1 -E '^LEVEL:' "$verdict" | awk '{print $2}')
if [ -n "$cli_level" ] && [ -n "$lvl" ] && [ "$cli_level" != "$lvl" ]; then
  echo "거부: --level $cli_level 인데 판정문은 'LEVEL: $lvl' 이다."; exit 1
fi
if [ -z "$lvl" ] && [ -n "$cli_level" ]; then
  echo "거부: --level $cli_level 인데 판정문에 'LEVEL: $cli_level' 줄이 없다."
  echo "  레벨은 렌즈가 자기 판정문에 적어야 영수증에 남는다. 플래그는 대조용일 뿐이다."; exit 1
fi
if [ -z "$lvl" ]; then
  lvl=$(jq -r '.default_level' "$J")
  echo "경고: 'LEVEL:' 줄이 없다 → '$lvl' 로 본다(옛 규칙). 렌즈에 레벨을 선언시켜라."
fi
# 빈 앞 필드를 IFS=탭 read 가 삼킨다 — required 는 빌 수 있으니 마지막에 둔다.
spec=$(jq -r --arg L "$lvl" '.levels[$L] // empty
  | [.min_distinct, (.majority_refutation.min_refuters // 0), (.deprecated // false), (.required|join(" "))] | @tsv' "$J")
[ -n "$spec" ] || { echo "거부: 모르는 레벨 '$lvl'. 가능: $(jq -r '.levels|keys_unsorted|join(", ")' "$J")"; exit 1; }
IFS=$'\t' read -r mind minref dep req <<<"$spec"
if [ "$dep" = "true" ] && [ "${LENS_STRICT:-0}" = "1" ]; then
  echo "거부: LENS_STRICT=1 — 레벨 '$lvl' 은 못 쓴다. --level premise|claim|light|essential|full 중에 골라라."; exit 1
fi
# BSD awk 는 한글 비교가 깨지고 기본 로케일 sort -u 는 한글 이름을 뭉갠다 — jq 와 LC_ALL=C 로 한다.
toks=$(grep -E '^LENS:' "$verdict" | awk '{print $2}' | LC_ALL=C sort -u)
nums=$(printf '%s\n' "$toks" | jq -Rs --slurpfile L "$J" -r '
  ($L[0].lenses|to_entries|map(.key as $n|(.value.alias[],$n)|{(.):$n})|add) as $m
  | split("\n") | map(select(length>0)) as $t
  | ($t|map($m[.] // empty)|unique|.[]), ("?"+($t|map(select($m[.]==null))|join(" ")))')
unknown=$(printf '%s\n' "$nums" | sed -n 's/^?//p')
lenses=$(printf '%s\n' "$nums" | grep -cE '^[0-9]+$' || true)
[ -z "${unknown// /}" ] || echo "경고: 모르는 렌즈 이름은 안 센다 → $unknown  (별칭표: $J)"
[ "${lenses:-0}" -ge "$mind" ] || {
  echo "거부: 서로 다른 렌즈가 ${lenses:-0} 개뿐이다(레벨 $lvl 은 최소 $mind)."
  echo "  'LENS: <번호|이름> <판정>' 형식으로 적어라. 에이전트 하나가 여러 축을 본 것은 렌즈 하나로 친다."
  fail=1
}
for n in $req; do
  printf '%s\n' "$nums" | grep -qx "$n" || {
    echo "거부: 레벨 $lvl 의 필수 렌즈 $n($(jq -r --arg n "$n" '.lenses[$n].name' "$J"))가 없다."; fail=1; }
done
if [ "${minref:-0}" -gt 0 ]; then
  r=$(grep -E '^REFUTE:' "$verdict" | awk '{print $2}' | LC_ALL=C sort -u | grep -c . || true)
  [ "$r" -ge "$minref" ] || { echo "거부: 독립 반박자가 $r 명뿐이다(레벨 $lvl 은 최소 $minref)."; fail=1; }
  if grep -qE '^REFUTE:.*refuted=true' "$verdict"; then
    echo "거부: refuted=true 인 반박자가 있다 → 집계는 다수결이 아니다. 하나면 막는다."; fail=1
  fi
fi
# 미반영은 CONCERN·BLOCK 만 본다. NIT 은 사유와 함께 남아도 된다.
bad_open=$(grep -iE '미반영|반영 안|unresolved' "$verdict" | grep -E 'CONCERN|BLOCK' || true)
if [ -n "$bad_open" ]; then
  echo "거부: 반영 안 된 CONCERN·BLOCK 이 남았다 →"; echo "$bad_open"; fail=1
fi
[ "$fail" -eq 0 ] || exit 1

dir="$HOME/.claude/lens-verdicts"; mkdir -p "$dir"
h=$(shasum -a 256 "$body" | cut -d' ' -f1)
{ printf '%s\t%s\t레벨 %s\t렌즈 %s개\n' "$(date -u +%FT%TZ)" "$body" "$lvl" "$lenses"; cat "$verdict"; } > "$dir/$h"
echo "렌즈 영수증 $h  (레벨 $lvl, 렌즈 ${lenses}개)"
