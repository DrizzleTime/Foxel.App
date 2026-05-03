#!/usr/bin/env bash
set -euo pipefail

flutter build apk --release --split-per-abi
