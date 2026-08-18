#!/usr/bin/env bash
set -euo pipefail

# Start Hugo development server with live reload
cd "$(dirname "$0")/hugo-site"
hugo server -D --bind 0.0.0.0 --port 1313
