#!/usr/bin/env python3
"""Real Sparkle updates using a loopback feed and an isolated, uniquely identified App."""
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import hashlib
import json
import os
import plistlib
import shutil
import subprocess
import tempfile
import threading
import uuid

ROOT = Path(__file__).resolve().parents[1]
SDK = ROOT / '.build/dependencies/Sparkle-2.10.0'
ACCOUNT = 'io.github.trojon99.siliconmeter'


def run(*args, **kwargs):
    kwargs.setdefault("timeout", 60)
    return subprocess.run(args, check=True, capture_output=True, text=True, **kwargs)


def update_plist(app, build, identifier):
    path = app / 'Contents/Info.plist'
    info = plistlib.loads(path.read_bytes())
    info.update(CFBundleVersion=str(build), CFBundleIdentifier=identifier,
                SUEnableAutomaticChecks=False, NSAppTransportSecurity={'NSAllowsLocalNetworking': True})
    path.write_bytes(plistlib.dumps(info))
    run('codesign', '--force', '--sign', '-', str(app))


def main():
    run('sh', str(ROOT / 'app/prepare-sparkle.sh'))
    harness = ROOT / '.build/UpdateHarness.app'
    (harness / 'Contents/MacOS').mkdir(parents=True, exist_ok=True)
    (harness / 'Contents/Frameworks').mkdir(parents=True, exist_ok=True)
    run('clang', '-O2', '-Wall', '-Wextra', '-Wno-unused-parameter', '-mmacosx-version-min=13.0',
        '-fobjc-arc', '-fblocks', '-F', str(SDK), str(ROOT / 'tests/update_harness.m'),
        '-framework', 'AppKit', '-framework', 'Sparkle', '-Wl,-rpath,@executable_path/../Frameworks',
        '-o', str(harness / 'Contents/MacOS/UpdateHarness'))
    (harness / 'Contents/Info.plist').write_bytes(plistlib.dumps({
        'CFBundleIdentifier': 'io.github.trojon99.siliconmeter.update-test',
        'CFBundleExecutable': 'UpdateHarness', 'CFBundleVersion': '1',
        'CFBundleShortVersionString': '1.0', 'CFBundlePackageType': 'APPL', 'LSUIElement': True,
        'NSAppTransportSecurity': {'NSAllowsLocalNetworking': True}}))
    run('ditto', str(SDK / 'Sparkle.framework'), str(harness / 'Contents/Frameworks/Sparkle.framework'))
    run('codesign', '--force', '--sign', '-', str(harness))
    results = []
    with tempfile.TemporaryDirectory(prefix='siliconmeter-update-test-') as temporary:
        work = Path(temporary)
        served = work / 'served'; served.mkdir()
        class QuietHandler(SimpleHTTPRequestHandler):
            def log_message(self, *args):
                pass
        server = ThreadingHTTPServer(('127.0.0.1', 0), partial(QuietHandler, directory=str(served)))
        thread = threading.Thread(target=server.serve_forever, daemon=True); thread.start()
        try:
            prefix = f'http://127.0.0.1:{server.server_port}'
            for mode in ('current', 'bad-feed', 'bad-archive', 'offline', 'install'):
                identifier = 'io.github.trojon99.siliconmeter.update-fixture.' + uuid.uuid4().hex
                target = work / mode / 'SiliconMeter.app'; target.parent.mkdir()
                run('ditto', str(ROOT / 'app/SiliconMeter.app'), str(target))
                update_plist(target, 3 if mode == 'current' else 2, identifier)
                original_info = (target / 'Contents/Info.plist').read_bytes()
                donor = work / ('donor-' + mode) / 'SiliconMeter.app'; donor.parent.mkdir()
                run('ditto', str(ROOT / 'app/SiliconMeter.app'), str(donor))
                update_plist(donor, 3, identifier)
                archive = served / (mode + '.zip')
                run('ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', str(donor), str(archive))
                signature = run(str(SDK / 'bin/sign_update'), '--account', ACCOUNT, '-p', str(archive)).stdout.strip()
                length = archive.stat().st_size
                feed = served / (mode + '.xml')
                feed.write_text(f'''<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
<channel><title>SiliconMeter test</title><item><title>Test 0.2.0</title>
<sparkle:version>3</sparkle:version><sparkle:shortVersionString>0.2.0</sparkle:shortVersionString>
<sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>
<enclosure url="{prefix}/{archive.name}" length="{length}" type="application/octet-stream" sparkle:edSignature="{signature}"/>
</item></channel></rss>\n''')
                run(str(SDK / 'bin/sign_update'), '--account', ACCOUNT, str(feed))
                run(str(SDK / 'bin/sign_update'), '--account', ACCOUNT, '--verify', str(feed))
                if mode == 'bad-feed':
                    feed.write_text(feed.read_text().replace('Test 0.2.0', 'Tampered update'))
                if mode == 'bad-archive':
                    with archive.open('ab') as out:
                        out.write(b'tampered')
                home = work / ('home-' + mode); home.mkdir()
                environment = dict(os.environ, CFFIXED_USER_HOME=str(home))
                url = prefix + ('/missing.xml' if mode == 'offline' else '/' + feed.name)
                result = subprocess.run([str(harness / 'Contents/MacOS/UpdateHarness'), str(target), url, mode],
                                        env=environment, capture_output=True, text=True, timeout=60)
                (ROOT / f'.build/update-{mode}.log').write_text(result.stdout + result.stderr)
                assert result.returncode == 0, (mode, result.stdout, result.stderr[-1500:])
                installed = plistlib.loads((target / 'Contents/Info.plist').read_bytes())
                assert installed['CFBundleIdentifier'] == identifier
                if mode == 'install':
                    assert installed['CFBundleVersion'] == '3'
                    assert (target / 'Contents/Info.plist').read_bytes() == (donor / 'Contents/Info.plist').read_bytes()
                    for name in ['MacOS/SiliconMeter', 'Resources/AppIcon.icns']:
                        assert hashlib.sha256((target / 'Contents' / name).read_bytes()).digest() == hashlib.sha256((donor / 'Contents' / name).read_bytes()).digest()
                    run('codesign', '--verify', '--strict', str(target))
                else:
                    assert (target / 'Contents/Info.plist').read_bytes() == original_info
                results.append({'mode': mode, 'result': 'PASS', 'build': installed['CFBundleVersion'],
                                'events': result.stdout.strip().splitlines()})
        finally:
            server.shutdown(); server.server_close(); thread.join(timeout=5)
    (ROOT / '.build/update-checks.json').write_text(json.dumps(results, indent=2) + '\n')
    print(json.dumps(results, indent=2))


if __name__ == '__main__':
    main()
