#!/bin/bash
# 로컬 빌드·테스트 편의 스크립트 (컨테이너에서 실행)
cd "$(dirname "$0")"
cabal build all 2>&1 | tee /tmp/build.log | grep -E 'rror|arning|Linking' | head -40
status=${PIPESTATUS[0]}
echo "BUILD_EXIT=$status"
if [ "$status" -ne 0 ]; then
  tail -30 /tmp/build.log
  exit "$status"
fi
cabal test 2>&1 | tail -60
