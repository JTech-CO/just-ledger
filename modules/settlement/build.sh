#!/bin/bash
# 모듈 빌드 — GnuCOBOL 3.2 의 cobol2014 예약어 사전에 NEAREST-EVEN 이 누락되어
# 있어(-std=default 사전에는 존재) -freserved= 로 보완한다. std 는 유지.
set -e
cd "$(dirname "$0")"
mkdir -p bin
COBC_FLAGS="-x -std=cobol2014 -freserved=NEAREST-EVEN -O2"
cobc $COBC_FLAGS -o bin/settle settle.cbl
cobc $COBC_FLAGS -o bin/amort amort.cbl
echo "settlement build OK (bin/settle, bin/amort)"
