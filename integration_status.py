#!/usr/bin/env python3
"""Integrationsstatus-Prüfung für Zerberus.

Dieses Skript fasst den Zustand der zentralen Netzwerkkomponenten
(NordVPN, Pi-hole, Unbound, WireGuard, Routing, IPs und Git-Repo)
zu einem kompakten Statusbericht zusammen.
"""
from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import textwrap
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable, List, Sequence

REPO_ROOT = Path(__file__).resolve().parent
DEFAULT_TIMEOUT = 6


@dataclass
class CommandOutcome:
    success: bool
    stdout: str
    stderr: str
    error: str | None
    returncode: int | None


@dataclass
class CheckResult:
    name: str
    status: str
    details: str


def run_cmd(cmd: Sequence[str], timeout: int) -> CommandOutcome:
    try:
        proc = subprocess.run(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=timeout,
            check=False,
        )
        return CommandOutcome(
            success=proc.returncode == 0,
            stdout=proc.stdout.strip(),
            stderr=proc.stderr.strip(),
            error=None if proc.returncode == 0 else f"exit {proc.returncode}",
            returncode=proc.returncode,
        )
    except FileNotFoundError:
        return CommandOutcome(success=False, stdout="", stderr="", error="command not found", returncode=None)
    except subprocess.TimeoutExpired as exc:
        stdout = (exc.stdout or "").strip()
        stderr = (exc.stderr or "").strip()
        return CommandOutcome(
            success=False,
            stdout=stdout,
            stderr=stderr,
            error=f"timeout after {timeout}s",
            returncode=None,
        )


def collapse(text: str) -> str:
    return " | ".join(part.strip() for part in text.splitlines() if part.strip())


def systemd_state(unit: str, timeout: int) -> tuple[str, str]:
    outcome = run_cmd(["systemctl", "is-active", unit], timeout)
    if not outcome.success:
        state = outcome.stdout or outcome.stderr or (outcome.error or "unknown")
        return state, state
    return outcome.stdout or "active", "active"


def git_status(timeout: int) -> CheckResult:
    status_out = run_cmd(["git", "-C", str(REPO_ROOT), "status", "-sb"], timeout)
    if not status_out.success:
        return CheckResult("Git-Repo", "WARN", f"git status fehlgeschlagen: {status_out.error or status_out.stderr}")

    upstream_out = run_cmd(["git", "-C", str(REPO_ROOT), "rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}"], timeout)
    if upstream_out.success:
        ahead_behind = run_cmd([
            "git",
            "-C",
            str(REPO_ROOT),
            "rev-list",
            "--count",
            "--left-right",
            "@{u}...HEAD",
        ], timeout)
        divergence = ahead_behind.stdout.replace("\t", " ") if ahead_behind.success else "divergence unbekannt"
        upstream_info = f"Upstream: {upstream_out.stdout} ({divergence.strip()})"
    else:
        upstream_info = "kein Upstream gesetzt"

    lines = status_out.stdout.splitlines()
    status_line = lines[0] if lines else "clean"
    dirty_suffix = "; lokale Änderungen" if len(lines) > 1 else ""
    repo_status = "OK" if len(lines) <= 1 else "INFO"
    details = f"{status_line}{dirty_suffix} | {upstream_info}"
    return CheckResult("Git-Repo", repo_status, details)


def check_nordvpn(timeout: int) -> CheckResult:
    detail_parts: List[str] = []
    cli = run_cmd(["nordvpn", "status", "--output", "json"], timeout)
    connected = False

    if cli.success and cli.stdout:
        try:
            data = json.loads(cli.stdout)
            status = str(data.get("Status", ""))
            connected = status.lower() == "connected"
            detail_parts.append(f"CLI: {status}")
            if connected:
                tech = data.get("Technology") or data.get("Protocol")
                detail_parts.append(f"Server: {data.get('City', 'unbekannt')} ({tech or 'n/a'})")
                detail_parts.append(f"IP: {data.get('IP', 'n/a')}")
        except json.JSONDecodeError:
            detail_parts.append(f"CLI unlesbar: {collapse(cli.stdout)}")
    elif cli.error == "command not found":
        detail_parts.append("CLI fehlt")
    else:
        detail_parts.append(f"CLI-Status nicht verfügbar ({cli.error or cli.stderr})")

    for unit in ("nordvpn-wrapper@auto.service", "nordvpnd.service"):
        state, detail = systemd_state(unit, timeout)
        detail_parts.append(f"{unit}: {detail}")
        if state == "active":
            connected = connected or unit.startswith("nordvpn-wrapper")

    status_value = "OK" if connected else "WARN"
    return CheckResult("NordVPN", status_value, " | ".join(detail_parts))


def check_pihole(timeout: int) -> CheckResult:
    outcome = run_cmd(["pihole", "status", "--json"], timeout)
    if outcome.success and outcome.stdout:
        try:
            data = json.loads(outcome.stdout)
            ftl = data.get("FTL", {}).get("status") or data.get("FTLstatus")
            status = "OK" if str(ftl).lower() == "running" else "WARN"
            detail = f"FTL: {ftl}" if ftl else "FTL-Status unbekannt"
            return CheckResult("Pi-hole", status, detail)
        except json.JSONDecodeError:
            pass

    state, detail = systemd_state("pihole-FTL.service", timeout)
    status_value = "OK" if state == "active" else "FAIL" if state in {"failed", "inactive"} else "WARN"
    return CheckResult("Pi-hole", status_value, f"pihole-FTL: {detail}")


def check_unbound(timeout: int) -> CheckResult:
    state, detail = systemd_state("unbound.service", timeout)
    status_value = "OK" if state == "active" else "FAIL" if state in {"failed", "inactive"} else "WARN"
    return CheckResult("Unbound", status_value, detail)


def check_wireguard(timeout: int) -> CheckResult:
    outcome = run_cmd(["wg", "show", "wg0"], timeout)
    if outcome.success:
        peers = sum(1 for line in outcome.stdout.splitlines() if line.strip().startswith("peer:"))
        handshake = next((line.strip() for line in outcome.stdout.splitlines() if "latest handshake" in line), "handshake n/a")
        detail = f"{peers} Peer(s); {handshake}"
        return CheckResult("WireGuard", "OK", detail)

    state, detail = systemd_state("wg0.service", timeout)
    status_value = "OK" if state == "active" else "FAIL" if state in {"failed", "inactive"} else "WARN"
    fallback_detail = detail if outcome.error != "command not found" else "wg CLI fehlt"
    return CheckResult("WireGuard", status_value, fallback_detail)


def check_routes(timeout: int) -> CheckResult:
    rules = run_cmd(["ip", "-4", "rule", "show"], timeout)
    main_route = run_cmd(["ip", "-4", "route", "show", "default"], timeout)
    vpn_route = run_cmd(["ip", "-4", "route", "show", "table", "vpn"], timeout)
    if not vpn_route.success:
        vpn_route = run_cmd(["ip", "-4", "route", "show", "table", "100"], timeout)

    detail_parts = [f"rules: {collapse(rules.stdout) if rules.success else rules.error}"]
    detail_parts.append(f"main: {collapse(main_route.stdout) if main_route.success else main_route.error}")
    if vpn_route.success:
        limited = ", ".join(vpn_route.stdout.splitlines()[:3]) if vpn_route.stdout else "leer"
        detail_parts.append(f"vpn: {limited}")
    else:
        detail_parts.append(f"vpn-table nicht lesbar ({vpn_route.error})")

    status_value = "OK" if rules.success and main_route.success else "WARN"
    return CheckResult("Routing", status_value, " | ".join(detail_parts))


def check_addresses(public_ip_url: str, timeout: int) -> CheckResult:
    addr_out = run_cmd(["ip", "-4", "addr", "show"], timeout)
    addresses = collapse(addr_out.stdout) if addr_out.success else addr_out.error or "ip addr fehlgeschlagen"
    public_out = run_cmd(["curl", "-4sS", "--max-time", str(timeout), public_ip_url], timeout)
    if public_out.success and public_out.stdout:
        public_info = public_out.stdout.strip()
        status_value = "OK"
    else:
        public_info = public_out.error or public_out.stderr or "öffentlich IP unbekannt"
        status_value = "WARN"
    details = f"local: {addresses} | public: {public_info}"
    return CheckResult("IPv4", status_value, details)


def format_table(results: Iterable[CheckResult]) -> str:
    rows = list(results)
    name_w = max(len(r.name) for r in rows + [CheckResult("Komponente", "", "")])
    status_w = max(len(r.status) for r in rows + [CheckResult("", "Status", "")])
    term_width = shutil.get_terminal_size(fallback=(100, 20)).columns
    details_w = max(20, term_width - name_w - status_w - 6)

    lines = [f"{'Komponente':<{name_w}}  {'Status':<{status_w}}  Details", "-" * term_width]
    for r in rows:
        wrapped = textwrap.wrap(r.details, width=details_w) or [""]
        lines.append(f"{r.name:<{name_w}}  {r.status:<{status_w}}  {wrapped[0]}")
        for cont in wrapped[1:]:
            lines.append(f"{'':<{name_w}}  {'':<{status_w}}  {cont}")
    return "\n".join(lines)


def aggregate_status(results: Iterable[CheckResult]) -> tuple[str, str]:
    priority = {"CRIT": 3, "FAIL": 3, "WARN": 2, "INFO": 1, "OK": 0}
    colors = {"CRIT": "\x1b[31m", "WARN": "\x1b[33m", "INFO": "\x1b[34m", "OK": "\x1b[32m"}
    best = "OK"
    for r in results:
        for candidate, level in priority.items():
            if r.status.upper() == candidate and level > priority.get(best, -1):
                best = candidate
    color = colors.get(best, "")
    reset = "\x1b[0m" if color else ""
    return best, f"Gesamtstatus: {color}{best}{reset}"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Integrationstest für Zerberus-Komponenten")
    parser.add_argument("--timeout", type=int, default=DEFAULT_TIMEOUT, help="Timeout pro Check (Sekunden)")
    parser.add_argument(
        "--public-ip-url",
        default="https://ifconfig.co/ip",
        help="Endpoint zur Ermittlung der öffentlichen IPv4 (default: https://ifconfig.co/ip)",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    checks = [
        check_nordvpn(args.timeout),
        check_pihole(args.timeout),
        check_unbound(args.timeout),
        check_wireguard(args.timeout),
        check_routes(args.timeout),
        check_addresses(args.public_ip_url, args.timeout),
        git_status(args.timeout),
    ]
    print("Zerberus Integrationsstatus")
    print(format_table(checks))
    overall, summary_line = aggregate_status(checks)
    print(summary_line)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
