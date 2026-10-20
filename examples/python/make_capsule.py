"""Write data_provenance.json next to a CSV, with the standard library only.

Usage: python3 make_capsule.py <csv path> <source url>
"""
import csv
import datetime
import hashlib
import json
import pathlib
import sys

if len(sys.argv) != 3:
    sys.exit("usage: python3 make_capsule.py <csv path> <source url>")
path, url = pathlib.Path(sys.argv[1]), sys.argv[2]

sha = hashlib.sha256(path.read_bytes()).hexdigest()   # what vrfcps() checks
with path.open(newline="") as f:
    rows = sum(1 for _ in csv.reader(f)) - 1           # data rows, header excluded

prov = {
    "name": path.stem,
    "source": {"url": url, "retrieved": datetime.date.today().isoformat()},
    "resource": {
        "filename": path.name,                         # relative to the capsule directory
        "sha256": sha,
        "size_bytes": path.stat().st_size,
        "row_count_data_rows": rows,
    },
}
(path.parent / "data_provenance.json").write_text(json.dumps(prov, indent=2) + "\n")
