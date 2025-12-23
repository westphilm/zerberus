#!/usr/bin/env python3
import argparse
import hashlib
import os
import shutil
import stat
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import List

try:
    import yaml  # type: ignore
except Exception as e:
    print("ERROR: PyYAML not available. Install with: sudo apt-get install -y python3-yaml", file=sys.stderr)
    raise

EXIT_OK = 0
EXIT_USAGE = 2
EXIT_NOT_ROOT = 3
EXIT_MANIFEST = 4
EXIT_DEPLOY = 5
EXIT_SYSTEMD = 6


@dataclass(frozen=True)
class FileEntry:
    src: Path
    dst: Path
    mode: int
    owner: str
    group: str


def log(msg: str) -> None:
    print(msg, flush=True)


def sha256_file(p: Path) -> str:
    h = hashlib.sha256()
    with p.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def ensure_parent_dir(dst: Path, dry_run: bool) -> None:
    parent = dst.parent
    if parent.is_dir():
        return
    log(f"  - mkdir -p {parent}")
    if not dry_run:
        parent.mkdir(parents=True, exist_ok=True)


def parse_mode(mode_str: str) -> int:
    # expects "0644" style
    if not isinstance(mode_str, str) or not mode_str.isdigit():
        raise ValueError(f"Invalid mode: {mode_str!r}")
    return int(mode_str, 8)


def resolve_user_group(owner: str, group: str) -> tuple[int, int]:
    import pwd
    import grp
    try:
        uid = pwd.getpwnam(owner).pw_uid
    except KeyError:
        raise ValueError(f"Unknown owner user: {owner}")
    try:
        gid = grp.getgrnam(group).gr_gid
    except KeyError:
        raise ValueError(f"Unknown group: {group}")
    return uid, gid


def load_manifest(manifest_path: Path, repo_root: Path) -> List[FileEntry]:
    if not manifest_path.is_file():
        raise FileNotFoundError(f"Manifest not found: {manifest_path}")

    data = yaml.safe_load(manifest_path.read_text(encoding="utf-8"))
    if not isinstance(data, dict) or "files" not in data or not isinstance(data["files"], list):
        raise ValueError("Manifest must contain top-level key: files: [ ... ]")

    base_dir = manifest_path.parent
    entries: List[FileEntry] = []
    for i, item in enumerate(data["files"], start=1):
        if not isinstance(item, dict):
            raise ValueError(f"Entry #{i} is not a mapping")

        for key in ("src", "dst", "mode", "owner", "group"):
            if key not in item:
                raise ValueError(f"Entry #{i} missing key: {key}")

        ## src = (repo_root / str(item["src"])).resolve()
        src_raw = Path(str(item["src"]))
        src_candidates = [base_dir / src_raw, repo_root / src_raw]
        src = next((c.resolve() for c in src_candidates if c.exists()), None)
        if src is None:
            raise FileNotFoundError(
                f"Entry #{i} source not found in manifest-relative or repo root: {src_raw}"
            )
        dst = Path(str(item["dst"]))

        if not str(dst).startswith("/"):
            raise ValueError(f"Entry #{i} dst must be absolute: {dst}")

        mode = parse_mode(str(item["mode"]))
        owner = str(item["owner"])
        group = str(item["group"])

        entries.append(FileEntry(src=src, dst=dst, mode=mode, owner=owner, group=group))

    return entries


def backup_path_for(dst: Path, backups_root: Path) -> Path:
    # "1 Ebene, überschreibend": stable backup location without timestamps.
    # Example: backups/etc/nftables.conf
    rel = str(dst).lstrip("/")
    return backups_root / rel


def backup_existing(dst: Path, bkp: Path, dry_run: bool) -> None:
    if not dst.exists():
        return
    if not dst.is_file():
        raise RuntimeError(f"Destination exists but is not a file: {dst}")

    log(f"  - backup {dst} -> {bkp}")
    if dry_run:
        return
    bkp.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(dst, bkp)


def files_equal(src: Path, dst: Path) -> bool:
    if not dst.exists() or not dst.is_file():
        return False
    # Fast path: size check
    if src.stat().st_size != dst.stat().st_size:
        return False
    # Content hash (robust)
    return sha256_file(src) == sha256_file(dst)


def deploy_one(entry: FileEntry, backups_root: Path, dry_run: bool) -> bool:
    """
    Returns True if changed, False if already up-to-date.
    """
    if not entry.src.is_file():
        raise FileNotFoundError(f"Source file missing: {entry.src}")

    changed = not files_equal(entry.src, entry.dst)

    if not changed:
        log(f"==> UP-TO-DATE: {entry.dst}")
        return False

    log(f"==> DEPLOY: {entry.src} -> {entry.dst}")

    ensure_parent_dir(entry.dst, dry_run=dry_run)

    # Backup always (if dst exists)
    bkp = backup_path_for(entry.dst, backups_root)
    backup_existing(entry.dst, bkp, dry_run=dry_run)

    # Atomic write: copy to temp in same dir then replace
    tmp = entry.dst.with_name(entry.dst.name + ".tmp.deploy")
    log(f"  - write temp {tmp}")
    if not dry_run:
        shutil.copy2(entry.src, tmp)

        uid, gid = resolve_user_group(entry.owner, entry.group)
        os.chown(tmp, uid, gid)
        os.chmod(tmp, entry.mode)

        os.replace(tmp, entry.dst)

    else:
        log(f"  - set owner/group {entry.owner}:{entry.group}, mode {oct(entry.mode)}")
        log(f"  - replace {tmp} -> {entry.dst}")

    return True


def systemd_daemon_reload(dry_run: bool) -> None:
    cmd = ["systemctl", "daemon-reload"]
    log("==> SYSTEMD: daemon-reload inited")
    if dry_run:
        log(f"  - (dry-run) would run: {' '.join(cmd)}")
        return
    proc = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    if proc.returncode != 0:
        raise RuntimeError(f"systemctl daemon-reload failed: {proc.stderr.strip()}")


def main() -> int:
    parser = argparse.ArgumentParser(description="Deploy zerberus system files from manifest.")
    parser.add_argument("--manifest", default="deploy/manifest.yaml", help="Path to manifest YAML (default: deploy/manifest.yaml)")
    parser.add_argument("--dry-run", action="store_true", help="Show actions, do not modify system")
    parser.add_argument("--systemd-reload", action="store_true", help="Run 'systemctl daemon-reload' after deploy")
    args = parser.parse_args()

    if os.geteuid() != 0:
        log("ERROR: run as root (use sudo).")
        return EXIT_NOT_ROOT

    repo_root = Path(__file__).resolve().parent
    manifest_path = (repo_root / args.manifest).resolve()

    backups_root = repo_root / "backups"
    if not args.dry_run:
        backups_root.mkdir(parents=True, exist_ok=True)

    log(f"Repo root:      {repo_root}")
    log(f"Manifest:       {manifest_path}")
    log(f"Backups root:   {backups_root}  (1-level, overwrite)")
    log(f"Dry-run:        {args.dry_run}")
    log("Verify:          false (global)")
    log(f"Systemd reload: {args.systemd_reload}")

    try:
        entries = load_manifest(manifest_path, repo_root=repo_root)
    except Exception as e:
        log(f"ERROR: manifest invalid: {e}")
        return EXIT_MANIFEST

    changed_any = False
    try:
        for e in entries:
            changed = deploy_one(e, backups_root=backups_root, dry_run=args.dry_run)
            changed_any = changed_any or changed
    except Exception as e:
        log(f"ERROR: deploy failed: {e}")
        return EXIT_DEPLOY

    # Service reload (systemd daemon-reload) - if requested
    if args.systemd_reload:
        try:
            log("==> SYSTEMD: daemon-reload triggered")
            systemd_daemon_reload(dry_run=args.dry_run)
        except Exception as e:
            log(f"ERROR: systemd reload failed: {e}")
            return EXIT_SYSTEMD
    else:
        log("==> SYSTEMD: daemon-reload skipped (default)")

    log("==> DONE")
    log(f"Changes applied: {changed_any}")
    return EXIT_OK


if __name__ == "__main__":
    raise SystemExit(main())
