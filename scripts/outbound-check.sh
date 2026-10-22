#!/usr/bin/env bash
# 외부로 나가는 모든 텍스트의 사실주장·처방을 뽑아 근거와 1:1 대조한다.
# gh pr create / gh issue create / gh pr comment / gh issue comment 앞에 반드시 통과시킨다.
#
#   outbound-check.sh <본문.md> <근거.txt> [--reply]
#
# 근거파일: 주장 한 건당 한 줄, 실제로 돌린 명령이나 파일:줄.
# --reply 는 댓글용으로, 실행 흔적 없는 근거를 거부한다.
set -u
body="${1:-}"; ev="${2:-}"; mode="${3:-}"
[ -f "$body" ] || { echo "usage: $0 <본문.md> <근거.txt> [--reply]"; exit 2; }

claims=$(awk '
  /^```/ { f = !f; next } f { next }
  {
    s = $0
    if (s ~ /`[^`]+`/ \
        || s ~ /[A-Za-z0-9_.\/-]+\.(java|kt|kts|properties|json|md|yml|yaml|toml|py|js|mjs|ts|tsx|jsx|go|rs|rb|php|c|h|cc|cpp|cs|swift|sh)/ \
        || s ~ /:[0-9]+/ \
        || s ~ /[Ss]hould|[Mm]ust|[Ww]ould|[Aa]dding|[Ll]ists|[Dd]ocuments|[Cc]overs/ \
        || s ~ /[0-9]+ (tests|errors|failures|constants|files)/) {
      gsub(/^[ \t>*+-]+/, "", s)
      if (length(s) > 15) print s
    }
  }' "$body")
n=$(printf '%s\n' "$claims" | grep -c . || true)

echo "── 검증이 필요한 주장 ${n} 건 ──"
printf '%s\n' "$claims" | grep . | nl -w2 -s'. '

if [ ! -f "$ev" ]; then
  echo; echo "거부: 근거파일 '$ev' 이 없다. 주장마다 실제로 돌린 명령을 한 줄씩 적어라."
  exit 1
fi
m=$(grep -c . "$ev" || true)
bad=$(grep -inE "reasoned|추론|아마|probably|likely|안 돌려|미확인|추정" "$ev" || true)
# 근거가 실행인지: 명령 흔적이나 파일:줄 이 있어야 한다
weak=$(grep -vnE '(\$|gradlew|mvn|curl|unzip|grep|git |javap|java -jar|npm|npx|pnpm|yarn|node|pytest|python|go (test|run|build)|cargo|make|ctest|docker|podman|gh |:[0-9]+)' "$ev" | grep . || true)

echo; echo "── 근거 ${m} 줄 ──"; nl -w2 -s'. ' "$ev"
fail=0
[ "$n" -gt 0 ] && [ "$m" -lt "$n" ] && { echo; echo "거부: 주장 ${n} 건인데 근거는 ${m} 줄뿐이다."; fail=1; }
[ -n "$bad" ] && { echo; echo "거부: 근거에 추론이 섞였다 →"; echo "$bad"; fail=1; }
# 베이스 이미지 범프는 태그·digest 확인이 아니라 빌드가 근거다.
if grep -qiE 'base image|docker image|FROM [a-z0-9./-]+:' "$body" "$ev" && ! grep -qE '(docker|podman|buildah) build' "$ev"; then
  echo; echo "거부: 이미지 범프인데 근거에 빌드 실행이 없다."; fail=1
fi
if [ "$mode" = "--reply" ] && [ -n "$weak" ]; then
  echo; echo "거부(답글 기준): 실행 흔적이 없는 근거가 있다 →"; echo "$weak"
  echo "  답글은 리뷰를 전제하지 않는 단언이다. 읽어서 안 것은 근거로 안 친다."
  fail=1
fi
# 첫 줄이 동조로 시작하면 거부한다 — 정보가 0이고 첫 사실의 자리를 먹는다.
head=$(grep -m1 . "$body" | sed 's/^[ \t>*+-]*//')
defer='지적하신|말씀하신|검토 감사|리뷰 감사|좋은 지적|정확한 지적|맞습니다|맞는 지적|Good catch|Great point|You.re right|Thank you for the review|Thanks for the review'
if printf '%s' "$head" | grep -qE "^($defer)"; then
  echo; echo "거부: 첫 줄이 동조로 연다 →"; echo "  $head"
  echo "  첫 줄은 사실로 연다 — 무엇을 돌렸고 무엇이 나왔는지. 동의는 그 사실이 대신한다."
  fail=1
fi

# 렌즈 게이트. 본문과 답글(레벨 claim 이상) 모두 본문 해시로 묶인 렌즈 영수증이 있어야 나간다.
{
  bh=$(shasum -a 256 "$body" | cut -d' ' -f1)
  if [ ! -f "$HOME/.claude/lens-verdicts/$bh" ]; then
    echo; echo "거부: 이 본문에 대한 렌즈 판정이 없다."
    echo "  본문을 **완성한 뒤** 그 본문과 diff 에 대고 독립 렌즈를 돌려라."
    # 안내문은 정의 파일에서 뽑는다 — 여기 렌즈 목록을 적으면 그게 스펙이 된다.
    lj="${LENS_LEVELS:-$(cd "$(dirname "$0")/.." && pwd)/skills/review-proof-prs/references/lens-levels.json}"
    if [ -f "$lj" ] && command -v jq >/dev/null; then
      echo "  레벨이 필수 렌즈를 정한다 ($lj):"
      jq -r '.levels|to_entries[]|select(.value.deprecated!=true)|"    \(.key): 렌즈 \(.value.required|join("·"))"' "$lj"
    fi
    echo "  렌즈 0(전제 파괴)은 어느 레벨에서도 못 뺀다. 판정문에 'LEVEL: <이름>' 을 적어라."
    echo "  끝나면: $(dirname "$0")/lens-record.sh --level <이름> '$body' <렌즈판정.md>"
    [ "$mode" = "--reply" ] && echo "  답글은 레벨 claim(렌즈 0·10)으로 돌린다: lens-record.sh --level claim '$body' <판정>"
    fail=1
  fi
  # 답글은 렌즈 10(본문)이 돈 레벨이어야 한다. 영수증 첫 줄: <시각>\t<경로>\t레벨 <이름>\t렌즈 N개
  if [ "$mode" = "--reply" ] && [ -f "$HOME/.claude/lens-verdicts/$bh" ] &&
     ! head -1 "$HOME/.claude/lens-verdicts/$bh" | grep -q -E '레벨 (claim|essential|full)'; then
    echo; echo "거부: 답글 영수증의 레벨이 claim 미만이다 — 렌즈 10(본문)이 안 돌았다."; fail=1
  fi
}

# 통과 영수증도 본문 해시로 남긴다 — gh 명령 앞 훅이 이것을 확인하게 할 수 있다.
if [ "$fail" -eq 0 ]; then
  rdir="$HOME/.claude/outbound-receipts"
  mkdir -p "$rdir"
  h=$(shasum -a 256 "$body" | cut -d' ' -f1)
  printf '%s\t%s\t%s\n' "$(date -u +%FT%TZ)" "$body" "${mode:-body}" > "$rdir/$h"
  echo; echo "통과. 영수증 $h"
fi
exit $fail
