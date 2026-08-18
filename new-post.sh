#!/usr/bin/env bash
set -euo pipefail

# Create a new Hugo blog post
cd "$(dirname "$0")/hugo-site"
TITLE="${1:-New Post}"
hugo new content "posts/${TITLE// /-}.md"
echo "✅ Created post: content/posts/${TITLE// /-}.md"
