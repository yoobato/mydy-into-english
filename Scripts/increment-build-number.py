#!/usr/bin/env python3
"""Reserve a unique build number; called once by the app target per build."""
import fcntl
import os
from pathlib import Path

root = Path(os.environ['SRCROOT'])
with (root / '.build-number.lock').open('w') as lock:
    fcntl.flock(lock, fcntl.LOCK_EX)
    counter = root / 'BuildNumber.txt'
    number = int(counter.read_text().strip()) + 1
    tmp = root / 'BuildNumber.txt.tmp'
    tmp.write_text(f'{number}\n')
    tmp.replace(counter)
    stamp = Path(os.environ['DERIVED_FILE_DIR']) / 'IntoEnglishBuildNumber.txt'
    stamp.parent.mkdir(parents=True, exist_ok=True)
    stamp.write_text(f'{number}\n')
print(f'Into English build number: {number}')
