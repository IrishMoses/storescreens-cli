#!/usr/bin/env python3
"""Generate the Homebrew formula from VERSION and a packaged release."""
import argparse
import hashlib
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("--tarball", type=Path, required=True)
parser.add_argument("--tap", type=Path, required=True)
args = parser.parse_args()
version = (Path(__file__).resolve().parents[1] / "VERSION").read_text().strip()
expected = f"storescreens-v{version}-macos.tar.gz"
if args.tarball.name != expected:
    parser.error(f"Expected {expected}, got {args.tarball.name}")
digest = hashlib.sha256(args.tarball.read_bytes()).hexdigest()
formula = f'''class Storescreens < Formula
  desc "Set up simulators, run XCUITests, and collect raw screenshots"
  homepage "https://github.com/ciscoriordan/storescreens-cli"
  url "https://github.com/ciscoriordan/storescreens-cli/releases/download/v{version}/{expected}"
  sha256 "{digest}"
  license "MIT"

  depends_on arch: :arm64
  depends_on macos: :sonoma

  def install
    libexec.install Dir["*"]
    bin.write_exec_script libexec/"storescreens"
    bin.write_exec_script libexec/"storescreens-mcp"
  end

  test do
    assert_match "{version}", shell_output("#{{bin}}/storescreens --version")
    assert_match "XCTAttachment", shell_output("#{{bin}}/storescreens setup --print-template")
  end
end
'''
path = args.tap / "Formula/storescreens.rb"
path.parent.mkdir(parents=True, exist_ok=True)
path.write_text(formula)
print(f"Wrote {path} for {version}")
