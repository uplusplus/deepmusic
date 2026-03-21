#!/bin/bash
set -e
cd "$(dirname "$0")"
echo "脚本所在目录: $(pwd)"

# Build
echo "Building..."
npx tsc --noEmit 2>&1 || {
  echo "TypeScript check failed"
  exit 1
}

# Run
echo "Starting server..."
exec npx tsx src/index.ts
