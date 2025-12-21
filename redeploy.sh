#!/usr/bin/env bash
set -euo pipefail

cd /opt/zerberus

git pull

sudo ./deploy.py --systemd-reload

sudo ./deploy.py --dry-run

sudo systemctl daemon-reload