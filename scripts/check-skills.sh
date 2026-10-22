#!/bin/bash
# 스킬 저장소 불변식 검사. 커밋 전에 돌린다.
cd "$(dirname "$0")/.."
fail=0

# 1) 빈 파일 금지 — 참조 파일이 다른 커밋에 묻어 조용히 비는 것을 잡는다
empty=$(find skills -type f -name '*.md' -empty)
if [ -n "$empty" ]; then
  echo "빈 마크다운 파일:"; echo "$empty" | sed 's/^/  /'; fail=1
fi

# 2) SKILL.md 가 가리키는 references/·assets/ 파일이 실재하고 비어있지 않은지
while IFS= read -r line; do
  f="${line%%:*}"; ref="${line#*:}"
  d="$(dirname "$f")/$ref"
  if [ ! -s "$d" ]; then
    echo "깨진/빈 참조: $f -> $ref"; fail=1
  fi
done < <(grep -rnoE '\((references|assets)/[A-Za-z0-9._-]+\.(md|json)\)' skills --include='SKILL.md' \
    | sed -E 's/:[0-9]+:\(/:/; s/\)$//')

# 3) agents/ 가 lenses/ 에서 새로 생성한 것과 같은가
scripts/build-lens-agents.sh --check >/dev/null || { echo "agents/ 낡음 — scripts/build-lens-agents.sh"; fail=1; }

[ $fail -eq 0 ] && echo "OK — 빈 파일 0, 참조 정상"
exit $fail
