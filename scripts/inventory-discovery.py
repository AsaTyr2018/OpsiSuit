#!/usr/bin/env python3
"""Network discovery helper for OpsiSuit inventory automation."""
from __future__ import annotations

import argparse
import concurrent.futures
import datetime as dt
import ipaddress
import json
import math
import os
import pathlib
import re
import shutil
import socket
import ssl
import subprocess
import sys
import time
import typing as t
import urllib.error
import urllib.request

PROJECT_ROOT = pathlib.Path(__file__).resolve().parents[1]
DEFAULT_CONFIG_PATH = PROJECT_ROOT / "configs" / "inventory" / "auto-inventory.yml"
DEFAULT_OUTPUT_DIR = PROJECT_ROOT / "data" / "inventory"
DEFAULT_CONFIG: dict[str, t.Any] = {
    "enabled": True,
    "subnets": ["192.168.1.0/24"],
    "exclude_addresses": ["192.168.1.1"],
    "ping": {
        "binary": "ping",
        "count": 1,
        "timeout_ms": 750,
        "workers": 64,
    },
    "discovery": {
        "dns_lookup": True,
        "capture_mac": True,
    },
    "opsi": {
        "api_url": "https://opsi.local:4447/rpc",
        "username": "opsiadmin",
        "password": "ChangeMeAdmin!",
        "verify_ssl": True,
        "ca_bundle": None,
        "request_timeout": 10,
    },
    "registration": {
        "auto_register": False,
        "client_id_template": "{hostname}.{domain}",
        "fallback_domain": "opsi.local",
        "default_group": "inventory-auto",
        "notes": "Discovered via automated inventory scan",
        "inventory_number": "",
        "trigger_hwscan": True,
    },
    "output": {
        "directory": str(DEFAULT_OUTPUT_DIR.relative_to(PROJECT_ROOT)),
        "max_history": 30,
    },
}

VERBOSE = False


def log(level: str, message: str) -> None:
    print(f"[{level}] {message}")


def log_info(message: str) -> None:
    log("INFO", message)


def log_warning(message: str) -> None:
    log("WARN", message)


def log_error(message: str) -> None:
    log("ERROR", message)


def log_debug(message: str) -> None:
    if VERBOSE:
        log("DEBUG", message)


def deep_merge(base: dict[str, t.Any], override: dict[str, t.Any]) -> dict[str, t.Any]:
    result: dict[str, t.Any] = {}
    for key in base.keys() | override.keys():
        if key in base and key in override:
            base_value = base[key]
            override_value = override[key]
            if isinstance(base_value, dict) and isinstance(override_value, dict):
                result[key] = deep_merge(base_value, override_value)
            else:
                result[key] = override_value
        elif key in override:
            result[key] = override[key]
        else:
            result[key] = base[key]
    return result


def resolve_path(value: str | None, *, default: pathlib.Path) -> pathlib.Path:
    if not value:
        return default
    path = pathlib.Path(value)
    if not path.is_absolute():
        path = PROJECT_ROOT / path
    return path


def load_config(config_path: pathlib.Path) -> dict[str, t.Any]:
    if not config_path.exists():
        log_warning(
            f"Configuration file {config_path} not found; using defaults."
        )
        return DEFAULT_CONFIG.copy()

    try:
        raw_text = config_path.read_text(encoding="utf-8")
    except OSError as exc:
        log_error(f"Failed to read configuration file {config_path}: {exc}")
        sys.exit(1)

    if not raw_text.strip():
        log_warning(f"Configuration file {config_path} is empty; using defaults.")
        return DEFAULT_CONFIG.copy()

    try:
        data = json.loads(raw_text)
    except json.JSONDecodeError as exc:
        log_error(
            "Configuration must contain valid JSON (YAML in JSON subset). "
            f"Error at line {exc.lineno}, column {exc.colno}: {exc.msg}"
        )
        sys.exit(1)

    if not isinstance(data, dict):
        log_error("Configuration root element must be an object/dictionary.")
        sys.exit(1)

    return deep_merge(DEFAULT_CONFIG, data)


def iter_addresses(subnets: list[str], exclude: set[str]) -> t.Iterator[str]:
    for subnet in subnets:
        try:
            network = ipaddress.ip_network(subnet, strict=False)
        except ValueError as exc:
            log_warning(f"Skipping invalid subnet {subnet!r}: {exc}")
            continue

        for host in network.hosts():
            ip = str(host)
            if ip in exclude:
                continue
            yield ip


def ensure_ping_command(ping_cfg: dict[str, t.Any]) -> list[str]:
    binary = ping_cfg.get("binary", "ping")
    binary_path = shutil.which(str(binary))
    if not binary_path:
        raise FileNotFoundError(f"Ping binary '{binary}' not found in PATH")

    count = max(1, int(ping_cfg.get("count", 1)))
    timeout_ms = max(1, int(ping_cfg.get("timeout_ms", 750)))
    timeout_seconds = max(1, math.ceil(timeout_ms / 1000))

    command = [binary_path, "-n", "-c", str(count), "-W", str(timeout_seconds)]
    extra_args = ping_cfg.get("extra_args", [])
    if extra_args:
        if not isinstance(extra_args, list):
            raise TypeError("ping.extra_args must be a list of strings")
        command.extend(str(arg) for arg in extra_args)
    return command


def ping_host(ip: str, ping_cfg: dict[str, t.Any]) -> dict[str, t.Any]:
    command = ensure_ping_command(ping_cfg) + [ip]
    start = time.monotonic()
    try:
        proc = subprocess.run(
            command,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=False,
        )
    except FileNotFoundError as exc:
        raise RuntimeError(f"Failed to execute ping command: {exc}") from exc

    duration_ms = (time.monotonic() - start) * 1000
    stdout = proc.stdout or ""
    stderr = proc.stderr or ""

    latency_match = re.search(r"time[=<]([0-9.]+)\s*ms", stdout)
    latency_ms: float | None = None
    if latency_match:
        try:
            latency_ms = float(latency_match.group(1))
        except ValueError:
            latency_ms = None

    reachable = proc.returncode == 0
    result: dict[str, t.Any] = {
        "ip": ip,
        "reachable": reachable,
        "latency_ms": latency_ms if reachable else None,
    }

    if not reachable:
        message = stderr.strip() or stdout.strip()
        if message:
            result["error"] = message
        result["latency_ms"] = None
    else:
        if latency_ms is None:
            result["latency_ms"] = round(duration_ms, 2)

    return result


def reverse_lookup(ip: str) -> str | None:
    try:
        hostname, _, _ = socket.gethostbyaddr(ip)
    except (socket.herror, socket.gaierror):
        return None
    if hostname:
        return hostname.rstrip(".")
    return None


def lookup_mac(ip: str) -> str | None:
    try:
        proc = subprocess.run(
            ["ip", "neigh", "show", ip],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=False,
        )
        if proc.returncode == 0:
            match = re.search(r"lladdr\s+([0-9a-f:]{17})", proc.stdout, re.IGNORECASE)
            if match:
                return match.group(1).lower()
    except FileNotFoundError:
        pass

    try:
        proc = subprocess.run(
            ["arp", "-n", ip],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=False,
        )
        if proc.returncode == 0:
            match = re.search(r"((?:[0-9a-f]{2}:){5}[0-9a-f]{2})", proc.stdout, re.IGNORECASE)
            if match:
                return match.group(1).lower()
    except FileNotFoundError:
        return None

    return None


def write_report(
    output_dir: pathlib.Path,
    results: list[dict[str, t.Any]],
    max_history: int,
) -> pathlib.Path:
    output_dir.mkdir(parents=True, exist_ok=True)
    timestamp = dt.datetime.utcnow().replace(microsecond=0).isoformat().replace(":", "-")
    report_path = output_dir / f"discovery-{timestamp}Z.json"
    payload = {
        "generated_at": dt.datetime.utcnow().isoformat() + "Z",
        "results": results,
    }
    report_path.write_text(json.dumps(payload, indent=2), encoding="utf-8")

    latest_path = output_dir / "latest.json"
    latest_path.write_text(json.dumps(payload, indent=2), encoding="utf-8")

    history = sorted(
        (p for p in output_dir.glob("discovery-*.json") if p.is_file()),
        key=lambda p: p.stat().st_mtime,
    )
    if max_history > 0 and len(history) > max_history:
        for stale in history[:-max_history]:
            try:
                stale.unlink()
            except OSError:
                log_warning(f"Failed to remove old report {stale}")

    return report_path


def ensure_client_id(host: dict[str, t.Any], reg_cfg: dict[str, t.Any]) -> str:
    hostname = host.get("hostname")
    template = reg_cfg.get("client_id_template", "{hostname}.{domain}")
    fallback_domain = reg_cfg.get("fallback_domain", "opsi.local")

    if hostname:
        candidate = hostname
        if "." not in candidate:
            candidate = template.format(
                hostname=hostname,
                domain=fallback_domain,
                ip=host["ip"],
            )
    else:
        sanitized_ip = host["ip"].replace(".", "-")
        candidate = template.format(
            hostname=f"auto-{sanitized_ip}",
            domain=fallback_domain,
            ip=host["ip"],
        )

    return candidate.lower()


def build_notes(host: dict[str, t.Any], reg_cfg: dict[str, t.Any]) -> str:
    notes_template = reg_cfg.get("notes", "")
    if not notes_template:
        return ""
    try:
        return notes_template.format(**host)
    except Exception:
        return notes_template


def build_opsi_request_handler(opsi_cfg: dict[str, t.Any]) -> t.Callable[[str, list[t.Any]], t.Any]:
    api_url = opsi_cfg.get("api_url")
    username = opsi_cfg.get("username")
    password = opsi_cfg.get("password")

    if not api_url or not username or not password:
        raise ValueError("OPSI configuration requires api_url, username, and password")

    request_timeout = int(opsi_cfg.get("request_timeout", 10))
    verify_ssl = bool(opsi_cfg.get("verify_ssl", True))
    ca_bundle_value = opsi_cfg.get("ca_bundle")

    if ca_bundle_value:
        ca_bundle_path = resolve_path(str(ca_bundle_value), default=PROJECT_ROOT)
        if not ca_bundle_path.exists():
            raise FileNotFoundError(f"Specified CA bundle {ca_bundle_path} does not exist")
        context = ssl.create_default_context(cafile=str(ca_bundle_path))
    elif verify_ssl:
        context = ssl.create_default_context()
    else:
        context = ssl._create_unverified_context()

    password_mgr = urllib.request.HTTPPasswordMgrWithDefaultRealm()
    password_mgr.add_password(None, api_url, username, password)

    handlers: list[urllib.request.BaseHandler] = [
        urllib.request.HTTPBasicAuthHandler(password_mgr)
    ]
    handlers.append(urllib.request.HTTPSHandler(context=context))
    opener = urllib.request.build_opener(*handlers)

    def call(method: str, params: list[t.Any]) -> t.Any:
        payload = json.dumps({"id": int(time.time() * 1000), "method": method, "params": params}).encode("utf-8")
        request = urllib.request.Request(
            api_url,
            data=payload,
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        log_debug(f"Calling OPSI method {method} with params {params}")
        try:
            with opener.open(request, timeout=request_timeout) as response:
                response_payload = response.read().decode("utf-8")
        except urllib.error.HTTPError as exc:
            raise RuntimeError(f"OPSI API HTTP error {exc.code}: {exc.reason}") from exc
        except urllib.error.URLError as exc:
            raise RuntimeError(f"OPSI API connection failed: {exc.reason}") from exc

        try:
            decoded = json.loads(response_payload)
        except json.JSONDecodeError as exc:
            raise RuntimeError(
                f"Invalid JSON response from OPSI API: {exc.msg}"
            ) from exc

        if decoded.get("error"):
            raise RuntimeError(f"OPSI API error: {decoded['error']}")

        return decoded.get("result")

    return call


def register_clients(
    hosts: list[dict[str, t.Any]],
    opsi_cfg: dict[str, t.Any],
    reg_cfg: dict[str, t.Any],
) -> tuple[list[str], list[str]]:
    try:
        call_opsi = build_opsi_request_handler(opsi_cfg)
    except Exception as exc:
        log_error(f"Skipping registration: {exc}")
        return [], [str(exc)]

    registered: list[str] = []
    failures: list[str] = []

    for host in hosts:
        client_id = ensure_client_id(host, reg_cfg)
        notes = build_notes(host, reg_cfg)
        host_payload = {
            "id": client_id,
            "hardwareAddress": host.get("mac"),
            "ipAddress": host.get("ip"),
            "description": notes,
            "notes": notes,
        }

        try:
            existing = call_opsi("host_getObjects", [[], {"id": client_id}])
        except Exception as exc:
            failures.append(f"{client_id}: failed to query existing clients ({exc})")
            continue

        if existing:
            log_info(f"Client {client_id} already present; skipping creation.")
            continue

        try:
            call_opsi("host_createOpsiClient", [host_payload])
            log_info(f"Registered new OPSI client {client_id} ({host['ip']}).")
            registered.append(client_id)
        except Exception as exc:
            inventory_number = reg_cfg.get("inventory_number", "")
            fallback_params: list[t.Any] = [
                client_id,
                host.get("mac"),
                host.get("ip"),
                notes or "",
            ]
            if inventory_number:
                fallback_params.append(inventory_number)

            try:
                call_opsi("host_createOpsiClient", fallback_params)
                log_info(
                    f"Registered new OPSI client {client_id} ({host['ip']}) using fallback signature."
                )
                registered.append(client_id)
            except Exception as inner_exc:
                failures.append(
                    f"{client_id}: creation failed ({exc}); fallback failed ({inner_exc})"
                )
                log_warning(
                    f"Failed to create client {client_id}: {exc}; fallback attempt: {inner_exc}"
                )
                continue

        if reg_cfg.get("trigger_hwscan", True):
            try:
                call_opsi(
                    "setProductActionRequest",
                    ["auditHardware", client_id, "setup"],
                )
                log_debug(f"Queued auditHardware for {client_id}.")
            except Exception as exc:
                log_warning(
                    f"Could not enqueue hardware inventory for {client_id}: {exc}"
                )

    return registered, failures


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Discover hosts on configured subnets and optionally register them "
            "with the OPSI server for automated inventory runs."
        )
    )
    parser.add_argument(
        "--config",
        default=str(DEFAULT_CONFIG_PATH),
        help="Path to auto-inventory configuration (JSON/YAML in JSON subset).",
    )
    parser.add_argument(
        "--output-dir",
        help="Override output directory for discovery reports.",
    )
    parser.add_argument(
        "--subnet",
        action="append",
        dest="subnets",
        help="Additional subnet to scan (can be supplied multiple times).",
    )
    parser.add_argument(
        "--max-workers",
        type=int,
        help="Override worker pool size used for probing hosts.",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Collect results but skip writing reports or registering clients.",
    )
    parser.add_argument(
        "--skip-registration",
        action="store_true",
        help="Do not register discovered hosts with OPSI even if enabled in config.",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="Execute even if the configuration has enabled=false.",
    )
    parser.add_argument(
        "--verbose",
        action="store_true",
        help="Enable verbose debug logging output.",
    )
    return parser.parse_args()


def main() -> int:
    global VERBOSE
    args = parse_args()
    VERBOSE = args.verbose

    config_path = resolve_path(args.config, default=DEFAULT_CONFIG_PATH)
    config = load_config(config_path)

    if not config.get("enabled", True) and not args.force:
        log_info("Automatic inventory discovery is disabled in configuration.")
        return 0

    subnets = list(config.get("subnets", []))
    if args.subnets:
        subnets.extend(args.subnets)
    if not subnets:
        log_error("No subnets configured for discovery; aborting.")
        return 1

    exclude_addresses = set(config.get("exclude_addresses", []))
    ping_cfg = config.get("ping", {})
    try:
        ensure_ping_command(ping_cfg)
    except Exception as exc:
        log_error(str(exc))
        return 1

    workers = args.max_workers or ping_cfg.get("workers")
    if not workers:
        cpu_count = os.cpu_count() or 4
        workers = min(256, max(16, cpu_count * 4))
    else:
        workers = max(1, int(workers))

    log_info(
        f"Starting discovery across {len(subnets)} subnet(s) using {workers} workers."
    )

    addresses = list(iter_addresses(subnets, exclude_addresses))
    if not addresses:
        log_warning("No IP addresses to scan after applying exclusions.")
        return 0

    log_info(f"Probing {len(addresses)} address(es). This may take a while...")

    results: list[dict[str, t.Any]] = []
    reachable_hosts: list[dict[str, t.Any]] = []

    dns_enabled = bool(config.get("discovery", {}).get("dns_lookup", True))
    capture_mac = bool(config.get("discovery", {}).get("capture_mac", True))

    with concurrent.futures.ThreadPoolExecutor(max_workers=workers) as executor:
        future_map = {executor.submit(ping_host, ip, ping_cfg): ip for ip in addresses}
        try:
            for future in concurrent.futures.as_completed(future_map):
                result = future.result()
                if result["reachable"]:
                    if dns_enabled:
                        hostname = reverse_lookup(result["ip"])
                        if hostname:
                            result["hostname"] = hostname
                    if capture_mac:
                        mac = lookup_mac(result["ip"])
                        if mac:
                            result["mac"] = mac
                    reachable_hosts.append(result)
                    log_debug(
                        f"Host {result['ip']} reachable (hostname={result.get('hostname')}, "
                        f"latency={result.get('latency_ms')} ms)."
                    )
                results.append(result)
        except KeyboardInterrupt:
            log_warning("Discovery interrupted by user.")
            return 1
        except Exception as exc:
            log_error(f"Unhandled discovery error: {exc}")
            return 1

    log_info(
        f"Discovery complete: {len(reachable_hosts)} reachable host(s) out of {len(results)} probed."
    )

    output_cfg = config.get("output", {})
    output_dir = resolve_path(
        args.output_dir or output_cfg.get("directory"),
        default=DEFAULT_OUTPUT_DIR,
    )
    max_history = int(output_cfg.get("max_history", 30))

    if not args.dry_run:
        report_path = write_report(output_dir, results, max_history)
        log_info(f"Discovery report written to {report_path.relative_to(PROJECT_ROOT)}")
    else:
        log_info("Dry-run enabled: skipping report generation and registration.")
        report_path = None

    registration_cfg = config.get("registration", {})
    auto_register = (
        not args.skip_registration
        and not args.dry_run
        and bool(registration_cfg.get("auto_register", False))
    )

    if auto_register and reachable_hosts:
        log_info("Attempting to register reachable hosts with OPSI API...")
        registered, failures = register_clients(
            reachable_hosts,
            config.get("opsi", {}),
            registration_cfg,
        )
        if registered:
            log_info(f"Successfully registered {len(registered)} client(s).")
        if failures:
            for failure in failures:
                log_warning(failure)
    elif auto_register:
        log_info("No reachable hosts detected; skipping registration.")

    if report_path and not args.dry_run:
        log_info("Automatic inventory discovery finished successfully.")

    return 0


if __name__ == "__main__":
    sys.exit(main())
