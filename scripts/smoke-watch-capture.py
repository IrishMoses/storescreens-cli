#!/usr/bin/env python3
"""Validate Watch capture using generated apps and owned simulator devices.

Run --sanity for one watch-only capture before the full CLI/MCP regression.
Requires Xcode with watchOS/iOS runtimes, xcodegen, and built StoreScreens binaries.
Artifacts are retained; only the simulators created by this run are removed.
"""
import argparse
import hashlib
import json
from pathlib import Path
import struct
import subprocess
import tempfile
import uuid

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument("--sanity", action="store_true")
parser.add_argument("--companion-only", action="store_true", help="Run the paired fixture without repeating watch-only checks")
args = parser.parse_args()
if args.sanity and args.companion_only:
    parser.error("--sanity and --companion-only cannot be combined")
ARTIFACTS = Path(tempfile.mkdtemp(prefix="storescreens-watch-"))
CLI = ROOT / ".build/debug/storescreens"
MCP = ROOT / ".build/debug/storescreens-mcp"
owned = []
names = []


def run(*command, **kwargs):
    print("Running:", " ".join(map(str, command)), flush=True)
    return subprocess.run(list(map(str, command)), check=True, **kwargs)


def simulator(kind):
    data = json.loads(run("xcrun", "simctl", "list", "devices", "available", "--json", capture_output=True, text=True).stdout)
    entries = [(runtime, device) for runtime, devices in data["devices"].items()
               for device in devices if f".{kind}-" in runtime]
    if kind == "iOS":
        entries = [(runtime, device) for runtime, device in entries
                   if ".iPhone-" in device["deviceTypeIdentifier"] and "Duo" not in device["deviceTypeIdentifier"]]
    runtime, base = sorted(entries, key=lambda item: item[0], reverse=True)[0]
    name = f"StoreScreensWatchSmoke-{kind}-{uuid.uuid4().hex[:8]}"
    result = run("xcrun", "simctl", "create", name, base["deviceTypeIdentifier"], runtime, capture_output=True, text=True)
    udid = result.stdout.strip()
    owned.append(udid)
    names.append(name)
    return name, udid


def hashes(directory):
    return {str(path.relative_to(directory)): hashlib.sha256(path.read_bytes()).hexdigest()
            for path in directory.rglob("*") if path.is_file()}


FLOW = '''        XCTAssertTrue(app.staticTexts["home"].waitForExistence(timeout: 15))
        takeScreenshot(named: "Home")
        app.buttons["details"].tap()
        XCTAssertTrue(app.staticTexts["detail"].waitForExistence(timeout: 15))
        takeScreenshot(named: "Detail")
'''


def fixture(companion):
    directory = ARTIFACTS / ("companion" if companion else "watch-only")
    for folder in ["Watch", "Phone", "WatchCaptureUITests"]:
        (directory / folder).mkdir(parents=True, exist_ok=True)
    (directory / "Watch/App.swift").write_text('''import SwiftUI
@main struct WatchCaptureApp: App {
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                VStack {
                    Text("Watch capture").accessibilityIdentifier("home")
                    NavigationLink("Open details") {
                        Text("A captured watch screen").accessibilityIdentifier("detail")
                    }.accessibilityIdentifier("details")
                }.navigationTitle("StoreScreens")
            }
        }
    }
}
''')
    (directory / "Phone/App.swift").write_text('''import SwiftUI
@main struct PhoneCaptureApp: App {
    var body: some Scene { WindowGroup { Text("Watch companion") } }
}
''')
    template = (ROOT / "Sources/storescreens-cli/Resources/ScreenshotTests.swift.template").read_text()
    source = directory / "WatchCaptureUITests/ScreenshotTests.swift"
    source.write_text(template.replace("{{SCREENSHOT_CALLS}}", FLOW))
    watch_settings = {"INFOPLIST_KEY_WKApplication": True, "INFOPLIST_KEY_WKWatchOnly": not companion,
                      "PRODUCT_BUNDLE_IDENTIFIER": "com.example.storescreens.watchsmoke.watch"}
    if companion:
        watch_settings["INFOPLIST_KEY_WKCompanionAppBundleIdentifier"] = "com.example.storescreens.watchsmoke.phone"
        watch_settings["PRODUCT_BUNDLE_IDENTIFIER"] = "com.example.storescreens.watchsmoke.phone.watch"
    targets = {
        "WatchCapture": {"type": "application", "platform": "watchOS", "deploymentTarget": "11.0",
                         "sources": ["Watch"], "settings": watch_settings},
        "WatchCaptureUITests": {"type": "bundle.ui-testing", "platform": "watchOS", "deploymentTarget": "11.0",
                                "sources": ["WatchCaptureUITests"], "dependencies": [{"target": "WatchCapture"}],
                                "settings": {"PRODUCT_BUNDLE_IDENTIFIER": "com.example.storescreens.watchsmoke.tests"}},
    }
    build_targets = {"WatchCapture": "all"}
    if companion:
        targets["PhoneCapture"] = {"type": "application", "platform": "iOS", "deploymentTarget": "18.0",
                                   "sources": ["Phone"], "settings": {"PRODUCT_BUNDLE_IDENTIFIER": "com.example.storescreens.watchsmoke.phone"},
                                   "dependencies": [{"target": "WatchCapture", "embed": True}]}
    schemes = {"WatchCapture": {"build": {"targets": build_targets}, "test": {"targets": ["WatchCaptureUITests"]}}}
    if companion:
        schemes["PhoneCapture"] = {"build": {"targets": {"PhoneCapture": "all"}}}
    project = {"name": "WatchCapture", "settings": {"base": {"GENERATE_INFOPLIST_FILE": True,
               "CODE_SIGNING_ALLOWED": False, "SWIFT_VERSION": "5.0", "SDK_STAT_CACHE_ENABLE": False}},
               "targets": targets, "schemes": schemes}
    spec = directory / "project.json"
    spec.write_text(json.dumps(project, indent=2))
    run("xcodegen", "generate", "--spec", spec, "--project", directory)
    watch_name, watch_id = simulator("watchOS")
    run(CLI, "init", "--scheme", "WatchCapture", cwd=directory)
    initial_config = (directory / "storescreens.yml").read_text()
    assert "platform: watchOS" in initial_config and "appearances: [dark]" in initial_config
    source.unlink()
    setup = run(CLI, "setup", "--scheme", "WatchCapture", "--non-interactive", cwd=directory, capture_output=True, text=True)
    print(setup.stdout, flush=True)
    assert "Found UI test target: WatchCaptureUITests" in setup.stdout
    assert source.exists() and "import XCTest" in source.read_text()
    source.write_text(template.replace("{{SCREENSHOT_CALLS}}", FLOW))
    device = {"simulator": watch_name, "platform": "watchOS"}
    if companion:
        phone_name, _ = simulator("iOS")
        device["companion"] = phone_name
        device["companion_scheme"] = "PhoneCapture"
    config = {"project": "WatchCapture.xcodeproj", "scheme": "WatchCapture", "devices": [device],
              "locales": ["en-US"], "test_target": "WatchCaptureUITests", "test_class": "ScreenshotTests",
              "screenshots": ["Home", "Detail"], "output_dir": "captures", "result_bundle_dir": "results",
              "derived_data_path": str(directory / "DerivedData"), "preflight": False}
    (directory / "storescreens.yml").write_text(json.dumps(config, indent=2))
    return directory, source, template, watch_id


def capture_mcp(directory, report, *extra):
    run("python3", ROOT / "examples/mcp-capture.py", "--server", MCP, "--directory", directory,
        "--report", directory / report, "--no-parallel", "--retries", "0", "--timeout", "900", *extra)


def verify_capture(directory):
    manifest = json.loads((directory / "captures/manifest.json").read_text())
    assert {shot["name"] for device in manifest["devices"] for shot in device["screenshots"]} == {"Home", "Detail"}
    assert all(device["appearance"] == "dark" and "Watch" in device["deviceType"] for device in manifest["devices"])
    for path in (directory / "captures").rglob("*.png"):
        data = path.read_bytes()
        assert data[:8] == b"\x89PNG\r\n\x1a\n"
        width, height = struct.unpack(">II", data[16:24])
        assert 150 < width < 600 and width < height < 700, (path, width, height)
    return manifest


try:
    print("Artifacts:", ARTIFACTS, flush=True)
    run("swift", "build", cwd=ROOT)
    if not args.companion_only:
        directory, source, template, watch_id = fixture(False)
        run(CLI, "prepare", cwd=directory)
        run(CLI, "capture", "--no-parallel", "--retries", "0", cwd=directory)
        verify_capture(directory)
        if not args.sanity:
            first_result = next((directory / "results").rglob("*.xcresult"))
            run(CLI, "collect", "--result-bundle", first_result, "--simulator", names[0],
                "--locale", "en-US", "--appearance", "dark", "--output", directory / "collected", cwd=directory)
            collected = json.loads((directory / "collected/manifest.json").read_text())
            assert {shot["name"] for device in collected["devices"] for shot in device["screenshots"]} == {"Home", "Detail"}
            detail = {path: value for path, value in hashes(directory / "captures").items() if path.endswith("Detail.png")}
            capture_mcp(directory, "partial.json", "--locales", "el", "--only", "Home")
            assert all(hashes(directory / "captures")[path] == value for path, value in detail.items())
            before = hashes(directory / "captures")
            failure = '        takeScreenshot(named: "Home")\n        XCTFail("Deliberate Watch capture failure")\n'
            source.write_text(template.replace("{{SCREENSHOT_CALLS}}", failure))
            capture_mcp(directory, "failure.json", "--expect-failure")
            assert hashes(directory / "captures") == before
            source.write_text(template.replace("{{SCREENSHOT_CALLS}}", FLOW))
            run(CLI, "capture", "--no-parallel", "--retries", "0", "--only", "Home", cwd=directory)
            run(CLI, "screenshot", "--udid", watch_id, "--output", directory / "raw-watch.png", cwd=directory)
    if not args.sanity:
        paired, paired_source, paired_template, _ = fixture(True)
        run(CLI, "prepare", cwd=paired)
        run(CLI, "capture", "--retries", "0", cwd=paired)
        verify_capture(paired)
        capture_mcp(paired, "capture.json")
        verify_capture(paired)
        detail = {path: value for path, value in hashes(paired / "captures").items() if path.endswith("Detail.png")}
        capture_mcp(paired, "partial.json", "--locales", "el", "--only", "Home")
        assert all(hashes(paired / "captures")[path] == value for path, value in detail.items())
        before = hashes(paired / "captures")
        failure = '        takeScreenshot(named: "Home")\n        XCTFail("Deliberate paired Watch capture failure")\n'
        paired_source.write_text(paired_template.replace("{{SCREENSHOT_CALLS}}", failure))
        capture_mcp(paired, "failure.json", "--expect-failure")
        assert hashes(paired / "captures") == before
        paired_source.write_text(paired_template.replace("{{SCREENSHOT_CALLS}}", FLOW))
        run(CLI, "capture", "--retries", "0", "--only", "Home", cwd=paired)
    (ARTIFACTS / "validation.json").write_text(json.dumps({"status": "passed", "sanity": args.sanity, "companion_only": args.companion_only}, indent=2))
    print("WATCH VALIDATION PASSED", flush=True)
finally:
    for udid in reversed(owned):
        subprocess.run(["xcrun", "simctl", "shutdown", udid], capture_output=True)
        subprocess.run(["xcrun", "simctl", "delete", udid], capture_output=True)
    for device_set in [[], ["--set", str(Path.home() / "Library/Developer/XCTestDevices")]]:
        result = subprocess.run(["xcrun", "simctl", *device_set, "list", "devices", "--json"], capture_output=True, text=True)
        if result.returncode:
            continue
        for devices in json.loads(result.stdout)["devices"].values():
            for device in devices:
                if any(device["name"].endswith(" of " + name) or device["name"] == name for name in names):
                    subprocess.run(["xcrun", "simctl", *device_set, "shutdown", device["udid"]], capture_output=True)
                    subprocess.run(["xcrun", "simctl", *device_set, "delete", device["udid"]], capture_output=True)
    print("Artifacts retained:", ARTIFACTS, flush=True)
