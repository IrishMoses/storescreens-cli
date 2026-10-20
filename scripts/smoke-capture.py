#!/usr/bin/env python3
"""Run real XCUITest capture and xcresult collection on an isolated simulator.

Requires Xcode, an iOS 27 runtime, and xcodegen. Keeps artifacts in a temporary
directory for inspection and removes only the simulator this script creates.
"""
import json
from pathlib import Path
import subprocess
import tempfile
import uuid

ROOT = Path(__file__).resolve().parents[1]
BINARY = ROOT / ".build/debug/storescreens"
ARTIFACTS = Path(tempfile.mkdtemp(prefix="storescreens-smoke-"))


def run(*args, **kwargs):
    print("Running:", " ".join(str(arg) for arg in args), flush=True)
    return subprocess.run([str(arg) for arg in args], check=True, **kwargs)


run("swift", "build", cwd=ROOT)
(ARTIFACTS / "App").mkdir()
(ARTIFACTS / "UITests").mkdir()
(ARTIFACTS / "App/App.swift").write_text('''import SwiftUI
@main struct CaptureSmokeApp: App {
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                VStack {
                    Text("Capture smoke test").accessibilityIdentifier("home")
                    NavigationLink("Open details") {
                        Text("A second authentic app screen").accessibilityIdentifier("detail")
                    }.accessibilityIdentifier("details")
                }.navigationTitle("StoreScreens")
            }
        }
    }
}
''')
template = (ROOT / "Sources/storescreens-cli/Resources/ScreenshotTests.swift.template").read_text()
flow = '''        XCTAssertTrue(app.staticTexts["home"].waitForExistence(timeout: 10))
        takeScreenshot(named: "Home")
        app.buttons["details"].tap()
        XCTAssertTrue(app.staticTexts["detail"].waitForExistence(timeout: 10))
        takeScreenshot(named: "Detail")
'''
(ARTIFACTS / "UITests/ScreenshotTests.swift").write_text(template.replace("{{SCREENSHOT_CALLS}}", flow))
(ARTIFACTS / "project.yml").write_text('''name: CaptureSmoke
options:
  bundleIdPrefix: com.example.storescreens
  deploymentTarget:
    iOS: "26.0"
settings:
  base:
    GENERATE_INFOPLIST_FILE: YES
    CODE_SIGNING_ALLOWED: NO
    TARGETED_DEVICE_FAMILY: "1,2"
targets:
  CaptureSmoke:
    type: application
    platform: iOS
    sources: [App]
  CaptureSmokeUITests:
    type: bundle.ui-testing
    platform: iOS
    sources: [UITests]
    dependencies:
      - target: CaptureSmoke
schemes:
  CaptureSmoke:
    build:
      targets:
        CaptureSmoke: all
    test:
      targets: [CaptureSmokeUITests]
''')
run("xcodegen", "generate", "--spec", ARTIFACTS / "project.yml", "--project", ARTIFACTS)
name = "StoreScreensSmoke-" + uuid.uuid4().hex[:8]
created = run("xcrun", "simctl", "create", name,
              "com.apple.CoreSimulator.SimDeviceType.iPhone-18-Pro",
              "com.apple.CoreSimulator.SimRuntime.iOS-27-0", capture_output=True, text=True)
udid = created.stdout.strip()
config = f'''project: CaptureSmoke.xcodeproj
scheme: CaptureSmoke
devices:
  - simulator: {name}
locales: [en-US]
appearances: [light]
screenshots: [Home, Detail]
test_target: CaptureSmokeUITests
test_class: ScreenshotTests
output_dir: captures
result_bundle_dir: results
preflight: false
'''
(ARTIFACTS / "storescreens.yml").write_text(config)
try:
    run(BINARY, "prepare", cwd=ARTIFACTS)
    run(BINARY, "capture", "--no-parallel", "--retries", "0", cwd=ARTIFACTS)
    manifest = json.loads((ARTIFACTS / "captures/manifest.json").read_text())
    names = {shot["name"] for device in manifest["devices"] for shot in device["screenshots"]}
    assert names == {"Home", "Detail"}, names
    for device in manifest["devices"]:
        for shot in device["screenshots"]:
            assert (ARTIFACTS / "captures" / shot["filename"]).stat().st_size > 1000
    run(BINARY, "capture", "--no-parallel", "--retries", "0", "--locale", "el", "--only", "Home", cwd=ARTIFACTS)
    narrowed = json.loads((ARTIFACTS / "captures/manifest.json").read_text())
    by_locale = {device["locale"]: {shot["name"] for shot in device["screenshots"]} for device in narrowed["devices"]}
    assert by_locale == {"en-US": {"Home", "Detail"}, "el": {"Home"}}, by_locale
    bundle = next((ARTIFACTS / "results").glob("*/*.xcresult"))
    run(BINARY, "collect", "--result-bundle", bundle, "--simulator", name,
        "--output", "collected", "--locale", "en-US", "--appearance", "light", cwd=ARTIFACTS)
    collected = json.loads((ARTIFACTS / "collected/manifest.json").read_text())
    collected_names = {shot["name"] for device in collected["devices"] for shot in device["screenshots"]}
    assert {"Home", "Detail"}.issubset(collected_names), collected_names
    print(f"Capture and collection passed. Artifacts: {ARTIFACTS}", flush=True)
finally:
    subprocess.run(["xcrun", "simctl", "shutdown", udid], capture_output=True)
    subprocess.run(["xcrun", "simctl", "delete", udid], check=True)
