#!/bin/zsh
# One-time setup: clones llama.cpp (pinned) and builds the macOS xcframework
# that Package.swift links against. Requires cmake (`brew install cmake`).
set -euo pipefail
cd "$(dirname "$0")/.."

LLAMA_COMMIT="000547513f1530346ecd163db8b3e13962949961"

if [[ ! -d vendor/llama.cpp ]]; then
    mkdir -p vendor
    git clone https://github.com/ggml-org/llama.cpp vendor/llama.cpp
fi
cd vendor/llama.cpp
git fetch --quiet
git checkout --quiet "$LLAMA_COMMIT"

# Our macOS-only trim of upstream's build-xcframework.sh lives in the repo
# (the vendor tree is gitignored), so refresh the copy here before running.
cp ../../scripts/build-xcframework-macos.sh .
./build-xcframework-macos.sh

echo "Done. Package.swift expects vendor/llama.cpp/build-apple/llama.xcframework — present:"
ls -d build-apple/llama.xcframework
