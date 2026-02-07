#!/bin/bash
set -e

cd "$(dirname "$0")/MathsChat"

echo "=== MathsChat Build Verification ==="
echo ""

echo "1. Checking Swift version..."
swift --version
echo ""

echo "2. Resolving package dependencies..."
swift package resolve
echo ""

echo "3. Building project..."
swift build
echo ""

echo "4. Checking for build artifacts..."
if [ -f ".build/debug/MathsChat" ]; then
    echo "✓ Debug executable found: .build/debug/MathsChat"
    ls -lh .build/debug/MathsChat
elif [ -f ".build/release/MathsChat" ]; then
    echo "✓ Release executable found: .build/release/MathsChat"
    ls -lh .build/release/MathsChat
else
    echo "✗ No executable found in .build/"
    echo "Build may have failed. Check output above for errors."
    exit 1
fi

echo ""
echo "=== Build verification complete ==="
