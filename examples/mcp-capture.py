#!/usr/bin/env python3
"""Run the StoreScreens stdio MCP workflow and save a machine-readable receipt.

Uses only the Python standard library. The application's capture configuration
and XCUITest harness remain the source of its device matrix and navigation.
"""
import argparse
import json
import os
from pathlib import Path
import re
import selectors
import signal
import subprocess
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--server", default="storescreens-mcp")
    parser.add_argument("--directory", type=Path, default=Path.cwd())
    parser.add_argument("--config", default="storescreens.yml")
    parser.add_argument("--report", type=Path, required=True)
    parser.add_argument("--locales", nargs="+", default=[])
    parser.add_argument("--appearances", nargs="+", default=[])
    parser.add_argument("--only")
    parser.add_argument("--no-parallel", action="store_true")
    parser.add_argument("--retries", type=int, default=1)
    parser.add_argument("--timeout", type=int, default=1800)
    parser.add_argument("--expect-failure", action="store_true")
    args = parser.parse_args()
    args.report = args.report.resolve()
    args.report.parent.mkdir(parents=True, exist_ok=True)
    receipt = {"calls": []}
    log_path = args.report.with_suffix(".stderr.log")
    with log_path.open("w") as stderr:
        process = subprocess.Popen([args.server], cwd=args.directory.resolve(), stdin=subprocess.PIPE,
                                   stdout=subprocess.PIPE, stderr=stderr, text=True, bufsize=1,
                                   start_new_session=True)
        reader = selectors.DefaultSelector()
        reader.register(process.stdout, selectors.EVENT_READ)
        sequence = 0

        def request(method, params):
            nonlocal sequence
            sequence += 1
            message = {"jsonrpc": "2.0", "id": sequence, "method": method, "params": params}
            process.stdin.write(json.dumps(message) + "\n")
            process.stdin.flush()
            deadline = time.monotonic() + 60
            while time.monotonic() < deadline:
                if not reader.select(timeout=1):
                    continue
                line = process.stdout.readline()
                if not line:
                    raise RuntimeError(f"MCP server exited; see {log_path}")
                response = json.loads(line)
                if response.get("id") != sequence:
                    continue
                receipt["calls"].append({"request": message, "response": response})
                if "error" in response:
                    raise RuntimeError(response["error"])
                return response["result"]
            raise TimeoutError(f"No response to {method}")

        def call(name, arguments):
            result = request("tools/call", {"name": name, "arguments": arguments})
            text = "\n".join(item["text"] for item in result.get("content", []) if item["type"] == "text")
            return result, text

        try:
            receipt["initialize"] = request("initialize", {
                "protocolVersion": "2024-11-05", "capabilities": {},
                "clientInfo": {"name": "storescreens-capture-example", "version": "1.0"},
            })
            process.stdin.write(json.dumps({"jsonrpc": "2.0", "method": "notifications/initialized"}) + "\n")
            process.stdin.flush()
            arguments = {"directory": str(args.directory.resolve()), "config_path": args.config,
                         "retries": args.retries, "no_parallel": args.no_parallel}
            if args.locales:
                arguments["locales"] = args.locales
            if args.appearances:
                arguments["appearances"] = args.appearances
            if args.only:
                arguments["only"] = args.only
            result, text = call("capture", arguments)
            if result.get("isError"):
                raise RuntimeError(text)
            task = re.search(r"taskId: ([a-z0-9]+)", text)
            if not task:
                raise RuntimeError(f"Missing task ID: {text}")
            receipt["task_id"] = task.group(1)
            deadline = time.monotonic() + args.timeout
            delay = 5
            while time.monotonic() < deadline:
                time.sleep(delay)
                result, text = call("get_capture_status", {"task_id": task.group(1)})
                status = text.splitlines()[0]
                print(status, flush=True)
                if status == "status: failed":
                    receipt["status"] = "failed"
                    receipt["error"] = text
                    if not args.expect_failure:
                        raise RuntimeError(text)
                    print("Capture failed as expected.", flush=True)
                    return
                if status == "status: completed":
                    if args.expect_failure:
                        raise RuntimeError("Capture unexpectedly succeeded")
                    if result.get("isError"):
                        raise RuntimeError(text)
                    capture = re.search(r"captureId: ([a-z0-9]+)", text)
                    result, text = call("get_capture_result", {"capture_id": capture.group(1)})
                    receipt["status"] = "completed"
                    receipt["manifest"] = json.loads(text.split("--- Manifest ---\n", 1)[1])
                    count = sum(len(device["screenshots"]) for device in receipt["manifest"]["devices"])
                    print(f"Capture complete: {count} manifest images. Receipt: {args.report}", flush=True)
                    return
                delay = 5 if "Wait 5 seconds" in text else 30
            raise TimeoutError("Capture exceeded --timeout")
        finally:
            args.report.write_text(json.dumps(receipt, indent=2, ensure_ascii=False) + "\n")
            reader.close()
            if process.poll() is None:
                os.killpg(process.pid, signal.SIGTERM)
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL)
                    process.wait()


if __name__ == "__main__":
    main()
