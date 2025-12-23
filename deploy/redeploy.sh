#!/usr/bin/env bash
set -euo pipefail

cd /opt/zerberus

git pull
sleep 1

sudo deploy/deploy.py --systemd-reload
sleep 1
sudo deploy/deploy.py --dry-run
