#!/usr/bin/env python3
"""Read-only database size snapshot for the long network comparison."""
from pathlib import Path
import json
import sqlite3
import sys
from datetime import datetime, timezone

root = Path(__file__).resolve().parents[1]
db = Path.home()/'Library/Application Support/Compute Monitor/telemetry.sqlite3'
with sqlite3.connect(f'file:{db}?mode=ro', uri=True) as c:
    row = {'utc':datetime.now(timezone.utc).isoformat(), 'phase':sys.argv[1],
           'page_count':c.execute('PRAGMA page_count').fetchone()[0],
           'page_size':c.execute('PRAGMA page_size').fetchone()[0],
           'freelist_count':c.execute('PRAGMA freelist_count').fetchone()[0],
           'integrity':c.execute('PRAGMA quick_check').fetchone()[0],
           'counts':{table:c.execute(f'SELECT count(*) FROM {table}').fetchone()[0]
                     for table in ('app_runs','fast_samples','slow_samples','events','writer_batches')},
           'files':{suffix or 'main':Path(str(db)+suffix).stat().st_size if Path(str(db)+suffix).exists() else 0
                    for suffix in ('','-wal','-shm')}}
out = root/'docs/results/network-db-size.jsonl'
with out.open('a') as f: f.write(json.dumps(row)+'\n')
print(json.dumps(row))
