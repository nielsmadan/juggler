import argparse
import json
import socket
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(
        description="Probe the Juggler iTerm2 daemon inside the guest"
    )
    parser.add_argument(
        "command",
        choices=("ping", "get_session_info", "activate", "highlight", "reset"),
    )
    parser.add_argument("--session")
    args = parser.parse_args()
    if args.command != "ping" and not args.session:
        parser.error("--session is required for this command")
    request = {"command": args.command, "session_id": args.session}
    if args.command == "highlight":
        request["tab"] = {"enabled": True, "color": [255, 165, 0], "duration": 2}
    path = Path.home() / "Library/Application Support/Juggler/iterm2_daemon.sock"
    with socket.socket(socket.AF_UNIX) as connection:
        connection.settimeout(5)
        connection.connect(str(path))
        connection.sendall(json.dumps(request).encode() + b"\n")
        with connection.makefile("r") as stream:
            response = json.loads(stream.readline())
    print(json.dumps(response))
    if response.get("status") != "ok":
        parser.exit(1, "Daemon command failed\n")


if __name__ == "__main__":
    main()
