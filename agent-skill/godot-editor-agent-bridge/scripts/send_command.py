#!/usr/bin/env python3
"""Send one JSON command to the GoTamata asset pipeline / Godot bridge server."""

from __future__ import annotations

import argparse
import json
import socket
import sys
import uuid
from typing import Any, Dict


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Send a command to the local GoTamata asset pipeline / Godot bridge server"
    )
    parser.add_argument("command", help="Command name, e.g. ping, editor_state, open_scene")
    parser.add_argument(
        "--args",
        default="{}",
        help="JSON object for command args (default: '{}')",
    )
    parser.add_argument("--host", default="127.0.0.1", help="Server host")
    parser.add_argument("--port", type=int, default=47891, help="Server port")
    parser.add_argument("--token", default="", help="Optional auth token")
    parser.add_argument("--id", default="", help="Optional request id")
    parser.add_argument(
        "--timeout", type=float, default=5.0, help="Socket timeout in seconds"
    )
    return parser.parse_args()


def build_request(args: argparse.Namespace) -> Dict[str, Any]:
    try:
        payload_args = json.loads(args.args)
    except json.JSONDecodeError as exc:
        raise SystemExit(f"--args must be valid JSON: {exc}") from exc

    if not isinstance(payload_args, dict):
        raise SystemExit("--args must decode to a JSON object")

    request_id = args.id or str(uuid.uuid4())
    request: Dict[str, Any] = {
        "id": request_id,
        "command": args.command,
        "args": payload_args,
    }
    if args.token:
        request["token"] = args.token
    return request


def send_request(host: str, port: int, timeout: float, request: Dict[str, Any]) -> Dict[str, Any]:
    wire = (json.dumps(request, separators=(",", ":")) + "\n").encode("utf-8")

    with socket.create_connection((host, port), timeout=timeout) as sock:
        sock.settimeout(timeout)
        sock.sendall(wire)

        chunks = []
        while True:
            chunk = sock.recv(4096)
            if not chunk:
                break
            chunks.append(chunk)
            if b"\n" in chunk:
                break

    if not chunks:
        raise SystemExit("No response received from server")

    raw = b"".join(chunks)
    line = raw.split(b"\n", 1)[0].decode("utf-8", errors="replace").strip()
    if not line:
        raise SystemExit("Received empty response line")

    try:
        data = json.loads(line)
    except json.JSONDecodeError as exc:
        raise SystemExit(f"Response was not valid JSON: {exc}; raw={line!r}") from exc

    if not isinstance(data, dict):
        raise SystemExit(f"Expected JSON object response, got: {type(data).__name__}")

    return data


def main() -> int:
    args = parse_args()
    request = build_request(args)
    response = send_request(args.host, args.port, args.timeout, request)

    print(json.dumps(response, indent=2, sort_keys=True))
    return 0 if bool(response.get("ok")) else 2


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (ConnectionError, TimeoutError, OSError) as exc:
        print(f"Connection failed: {exc}", file=sys.stderr)
        raise SystemExit(1) from exc
