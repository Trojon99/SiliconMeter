#!/usr/bin/env python3
"""One external snapshot of app process, child, and socket counts during A/B."""
from pathlib import Path
import json
import subprocess
import sys
from datetime import datetime, timezone

root = Path(__file__).resolve().parents[1]
app = str(root / 'app/ComputeMonitor.app/Contents/MacOS/ComputeMonitor')
rows = []
for line in subprocess.check_output(['ps', '-axo', 'pid=,ppid=,args='], text=True).splitlines():
    parts = line.strip().split(None, 2)
    if len(parts) == 3 and parts[0].isdigit() and parts[1].isdigit():
        rows.append((int(parts[0]), int(parts[1]), parts[2]))
pids = [pid for pid, _, args in rows if args == app]
assert len(pids) == 1, pids
pid = pids[0]
connections = subprocess.run(['lsof', '-nP', '-a', '-p', str(pid), '-i'],
                             capture_output=True, text=True).stdout.splitlines()
record = {'utc':datetime.now(timezone.utc).isoformat(),'phase':sys.argv[1],'pid':pid,
          'child_processes':sum(ppid == pid for _,ppid,_ in rows),
          'network_connections':max(0,len(connections)-1)}
out = root/'docs/results/network-process-observations.jsonl'
with out.open('a') as f: f.write(json.dumps(record)+'\n')
print(json.dumps(record))
