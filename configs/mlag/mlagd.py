#!/usr/bin/env python3
"""
Lab MLAG control daemon.

- UDP heartbeat between VTEP loopbacks.
- Peer-link carrier monitoring.
- Deterministic primary/secondary behavior.
- Fail-closed secondary when peer or peer-link is unavailable.
- Controls MLAG bonds only; EVPN MH bonds are never touched.

This is a lab control-plane prototype, not a production MLAG implementation.
"""

import json
import logging
import os
import signal
import socket
import subprocess
import sys
import time

CONFIG = sys.argv[1] if len(sys.argv) > 1 else "/etc/mlag/mlag.json"

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s mlagd %(levelname)s: %(message)s",
)
LOG = logging.getLogger("mlagd")

running = True


def stop_handler(_sig, _frame):
    global running
    running = False


signal.signal(signal.SIGTERM, stop_handler)
signal.signal(signal.SIGINT, stop_handler)


def run(args, check=True):
    result = subprocess.run(
        args,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    if check and result.returncode != 0:
        raise RuntimeError(
            f"{' '.join(args)}: {result.stderr.strip()}"
        )
    return result.stdout.strip()


def link_is_up(interface):
    path = f"/sys/class/net/{interface}/carrier"
    try:
        with open(path, "r", encoding="ascii") as f:
            return f.read().strip() == "1"
    except OSError:
        return False


def set_bond_state(interface, enabled):
    state = "up" if enabled else "down"
    run(["ip", "link", "set", "dev", interface, state], check=False)


def write_sysfs(path, value):
    """Write a sysfs attribute without O_TRUNC."""
    fd = os.open(path, os.O_WRONLY)
    try:
        data = str(value).encode("ascii")
        written = os.write(fd, data)
        if written != len(data):
            raise OSError(f"Short write to {path}: {written}/{len(data)}")
    finally:
        os.close(fd)


def set_lacp_identity(interface, system_mac, system_priority):
    base = f"/sys/class/net/{interface}/bonding"
    attributes = {
        "ad_actor_system": system_mac,
        "ad_actor_sys_prio": str(system_priority),
    }

    for name, value in attributes.items():
        path = os.path.join(base, name)

        if not os.path.exists(path):
            raise RuntimeError(f"Missing bonding attribute: {path}")

        fd = os.open(path, os.O_WRONLY)
        try:
            data = value.encode("ascii")
            written = os.write(fd, data)
            if written != len(data):
                raise RuntimeError(f"Short write to {path}")
        finally:
            os.close(fd)


def send_packet(sock, peer_ip, port, payload):
    try:
        sock.sendto(
            json.dumps(payload).encode("utf-8"),
            (peer_ip, port),
        )
    except OSError as exc:
        LOG.warning(
            "Heartbeat send failed: local=%s peer=%s:%s error=%s",
            sock.getsockname()[0],
            peer_ip,
            port,
            exc,
        )


def main():
    with open(CONFIG, "r", encoding="utf-8") as f:
        cfg = json.load(f)

    local_ip = cfg["local_vtep"]
    peer_ip = cfg["peer_vtep"]
    role = cfg["role"]
    port = int(cfg.get("heartbeat_port", 9876))
    interval = float(cfg.get("heartbeat_interval", 1))
    timeout = float(cfg.get("heartbeat_timeout", 3))
    peer_link = cfg["peer_link"]
    bonds = cfg["mlag_bonds"]

    if role not in ("primary", "secondary"):
        raise ValueError("role must be primary or secondary")

    # Configure each MLAG bond's common LACP identity.
    for bond in bonds:
        set_lacp_identity(
            bond["name"],
            bond["actor_system"],
            bond.get("actor_priority", 65535),
        )

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.bind((local_ip, port))
    sock.setblocking(False)

    peer_last_seen = 0.0
    last_log_state = None

    LOG.info(
        "Started role=%s local=%s peer=%s peer-link=%s",
        role, local_ip, peer_ip, peer_link
    )

    while running:
        now = time.monotonic()
        peer_link_up = link_is_up(peer_link)

        # Drain all queued heartbeat packets.
        while True:
            try:
                data, address = sock.recvfrom(4096)
            except BlockingIOError:
                break
            except OSError as exc:
                LOG.warning("Heartbeat receive error: %s", exc)
                break

            if address[0] != peer_ip:
                continue

            try:
                message = json.loads(data.decode("utf-8"))
            except (ValueError, UnicodeDecodeError):
                LOG.warning("Invalid heartbeat packet from %s", address[0])
                continue

            if message.get("domain") != cfg["domain"]:
                continue

            if message.get("node") != cfg["peer_node"]:
                continue

            # Reject stale packets.
            packet_time = message.get("time")
            if not isinstance(packet_time, (int, float)):
                continue

            if abs(time.time() - packet_time) > timeout:
                continue

            peer_last_seen = time.monotonic()

        peer_alive = (time.monotonic() - peer_last_seen) < timeout

        # Safety policy:
        # - Both links healthy: both peers can forward.
        # - Peer-link failed: only primary forwards.
        # - DAD heartbeat failed: only primary forwards.
        # - Secondary never self-promotes without a witness.
        if peer_alive and peer_link_up:
            forwarding = True
            state = "ACTIVE"
        elif role == "primary":
            forwarding = True
            state = "PRIMARY_DEGRADED"
        else:
            forwarding = False
            state = "SECONDARY_BLOCKED"

        for bond in bonds:
            set_bond_state(bond["name"], forwarding)

        if state != last_log_state:
            LOG.warning(
                "State=%s peer_alive=%s peer_link_up=%s forwarding=%s",
                state, peer_alive, peer_link_up, forwarding
            )
            last_log_state = state

        payload = {
            "domain": cfg["domain"],
            "node": cfg["node"],
            "role": role,
            "peer_link_up": peer_link_up,
            "state": state,
            "time": time.time(),
        }
        send_packet(sock, peer_ip, port, payload)

        time.sleep(interval)

    # Safe shutdown: block this node's MLAG bonds.
    for bond in bonds:
        set_bond_state(bond["name"], False)

    sock.close()
    LOG.info("Stopped; MLAG bonds administratively down")


if __name__ == "__main__":
    try:
        main()
    except Exception:
        LOG.exception("Fatal error")
        sys.exit(1)