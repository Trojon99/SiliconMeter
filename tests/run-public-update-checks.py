#!/usr/bin/env python3
"""Check the actual signed feed with Sparkle, using isolated hosts; never install."""
from pathlib import Path
import json
import os
import plistlib
import subprocess
import sys
import tempfile
import uuid

ROOT = Path(__file__).resolve().parents[1]

def main():
    url = sys.argv[1] if len(sys.argv) > 1 else 'https://raw.githubusercontent.com/Trojon99/SiliconMeter/main/updates/appcast.xml'
    harness = ROOT / '.build/UpdateHarness.app/Contents/MacOS/UpdateHarness'
    assert harness.exists(), 'Run tests/run-update-checks.py first to build the harness'
    results = []
    with tempfile.TemporaryDirectory(prefix='siliconmeter-update-test-') as temporary:
        work = Path(temporary)
        for mode, build in [('current', '3'), ('found', '2')]:
            host = work / mode / 'SiliconMeter.app'
            host.parent.mkdir()
            subprocess.run(['ditto', str(ROOT / 'app/SiliconMeter.app'), str(host)], check=True, timeout=30)
            path = host / 'Contents/Info.plist'
            info = plistlib.loads(path.read_bytes())
            info.update(CFBundleVersion=build, CFBundleIdentifier='io.github.trojon99.siliconmeter.feed-test.'+uuid.uuid4().hex,
                        SUEnableAutomaticChecks=False, NSAppTransportSecurity={'NSAllowsLocalNetworking': True})
            path.write_bytes(plistlib.dumps(info))
            subprocess.run(['codesign', '--force', '--sign', '-', str(host)], check=True, capture_output=True, timeout=30)
            before = path.read_bytes()
            home = work / ('home-'+mode); home.mkdir()
            result = subprocess.run([str(harness), str(host), url, mode], env=dict(os.environ, CFFIXED_USER_HOME=str(home)),
                                    capture_output=True, text=True, timeout=60)
            (ROOT / ('.build/public-update-'+mode+'.log')).write_text(result.stdout + result.stderr)
            assert result.returncode == 0, (mode, result.stdout, result.stderr)
            assert path.read_bytes() == before, 'Check-only flow changed the temporary App'
            results.append({'mode':mode, 'host_build':build, 'result':'PASS', 'events':result.stdout.splitlines()})
    (ROOT / '.build/public-update-checks.json').write_text(json.dumps(results, indent=2)+'\n')
    print(json.dumps(results, indent=2))

if __name__ == '__main__':
    main()
