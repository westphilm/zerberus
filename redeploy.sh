#!/usr/bin/env bash
set -euo pipefail

cd /opt/zerberus

git pull

sudo ./deploy.py --dry-run
sudo ./deploy.py
