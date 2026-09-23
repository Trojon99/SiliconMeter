#!/usr/bin/env python3
"""Read-only preservation check from both real pre-v3 and pre-v4 backups."""
from pathlib import Path
import json
import sqlite3

root = Path(__file__).resolve().parents[1]
db = Path.home()/'Library/Application Support/Compute Monitor/telemetry.sqlite3'
tables = ('app_runs','fast_samples','slow_samples','events','writer_batches','training_sessions')
result = {'database':'~/Library/Application Support/Compute Monitor/telemetry.sqlite3','backups':{}}
with sqlite3.connect(f'file:{db}?mode=ro',uri=True) as current:
    result['version'] = current.execute('PRAGMA user_version').fetchone()[0]
    result['integrity'] = current.execute('PRAGMA integrity_check').fetchone()[0]
    assert result['version'] == 4 and result['integrity'] == 'ok'
    result['current_counts'] = {table:current.execute(f'SELECT count(*) FROM {table}').fetchone()[0]
                                for table in tables}
    for label,glob in [('v2','pre-v3-*'),('v3','pre-v4-*')]:
        backup = sorted((root/'backups').glob(glob+'/consistent-telemetry.sqlite3'))[-1]
        with sqlite3.connect(f'file:{backup}?mode=ro',uri=True) as before:
            assert before.execute('PRAGMA user_version').fetchone()[0] == int(label[1])
            counts={}
            for table in tables:
                cols=','.join(r[1] for r in before.execute(f'PRAGMA table_info({table})'))
                original=before.execute(f'SELECT {cols} FROM {table}').fetchall()
                now=current.execute(f'SELECT {cols} FROM {table}').fetchall()
                missing=set(original)-set(now)
                if table == 'app_runs':
                    # Only the end timestamp may change for an earlier active run.
                    missing={row for row in missing if not (row[2] is None and any(
                        current_row[0:2] == row[0:2] and current_row[2] is not None
                        and current_row[3:] == row[3:] for current_row in now))}
                assert not missing,(label,table,len(missing))
                counts[table]=len(original)
            result['backups'][label]={'path':str(backup.relative_to(root)),'original_counts':counts,'all_rows_preserved':True}
    old_fast=result['backups']['v3']['original_counts']['fast_samples']
    old_unavailable=current.execute("SELECT count(*) FROM fast_samples WHERE network_rx_bytes_per_sec IS NULL AND network_tx_bytes_per_sec IS NULL AND network_rx_bytes_per_sec_quality='unavailable' AND network_tx_bytes_per_sec_quality='unavailable'").fetchone()[0]
    assert old_unavailable >= old_fast
    result['old_network_rows_unavailable']=old_unavailable
out=root/'docs/results/real-db-v4-check.json'
out.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
print(json.dumps(result,ensure_ascii=False))
