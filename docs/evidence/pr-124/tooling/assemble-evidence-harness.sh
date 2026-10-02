#!/bin/bash
# Assembles the evidence harness: compiles main.swift against the PR-built
# swiftmodules and links the PR-built object files. Throwaway — do not commit.
set -uo pipefail
cd "$(dirname "$0")/.."
TC=$HOME/Library/Developer/Toolchains/swift-6.2.4-RELEASE.xctoolchain
DEBUG=.build-toolchain/x86_64-apple-macosx/debug
OBJS=""
for t in CashRunwayCore CoreXLSX XMLCoder ZIPFoundation GRDB GRDBSQLCipher; do
  OBJS="$OBJS $DEBUG/$t.build"/*.o
done
"$TC/usr/bin/swiftc" \
  Sources/EvidenceHarness/main.swift \
  -module-name EvidenceHarness \
  -o .build-toolchain/evidence-runner \
  -enable-testing \
  -sdk /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk \
  -I "$DEBUG/Modules" \
  -I "$DEBUG" \
  -Xcc -fmodule-map-file="$PWD/Vendor/GRDB.swift/Sources/GRDBSQLCipher/include/module.modulemap" \
  $OBJS \
  -F "$DEBUG" \
  -framework SQLCipher \
  -framework Security \
  -Xlinker -rpath -Xlinker "$TC/usr/lib/swift/macosx" \
  -Xlinker -rpath -Xlinker "$PWD/$DEBUG" \
  2>&1
echo "LINK_EXIT:$?"