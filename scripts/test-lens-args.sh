#!/usr/bin/env bash
# lens-args.sh 의 에이전트 판정 자가검사.
set -u
cd "$(dirname "$0")/.."
A=skills/review-proof-prs/assets/lens-args.sh
fail=0
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/.claude/agents"
cp agents/lens-*.md "$tmp/.claude/agents/"
get() { python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["use_agents"], d["agent_prefix"])'; }
v=$(HOME="$tmp" $A /tmp | get)
[ "$v" = "True lens-" ] || { echo "11개 다 있는데 $v"; fail=1; }
rm "$tmp/.claude/agents/lens-7.md"
v=$(HOME="$tmp" $A /tmp | get)
[ "$v" = "False " ] || { echo "하나 빠졌는데 $v"; fail=1; }
# 플러그인 캐시에 설치된 사본은 <플러그인>:lens-<N> 을 쓴다
p="$tmp/.claude/plugins/cache/wantaekchoi/review-proof-prs/1.0.0"; mkdir -p "$p"
cp -R skills agents "$p/"
v=$(HOME="$tmp" "$p/$A" /tmp | get)
[ "$v" = "True review-proof-prs:lens-" ] || { echo "플러그인 설치본인데 $v"; fail=1; }
v=$(HOME="$tmp" LENS_AGENT_PREFIX=x:lens- $A /tmp | get)
[ "$v" = "True x:lens-" ] || { echo "LENS_AGENT_PREFIX 무시됨: $v"; fail=1; }
[ $fail = 0 ] && echo "통과"
exit $fail
