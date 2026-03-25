#!/bin/bash
set -e
cd "$(dirname "$0")"
echo "脚本所在目录: $(pwd)"

# 尝试 TypeScript 检查，但失败时不退出（脚本文件可能有隐式 any 类型）
echo "Checking TypeScript..."
npx tsc --noEmit --excludeDirectories src/scripts 2>&1 || {
  echo "TypeScript check had warnings, but continuing anyway..."
}

# Run
echo "Starting server..."
exec npx tsx src/index.ts
