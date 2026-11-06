"""Read-only live-app CPU collector. User sets playback state before invocation."""
import argparse
import datetime
import hashlib
import json
from pathlib import Path
import statistics
import subprocess
import time

parser = argparse.ArgumentParser()
parser.add_argument("case")
parser.add_argument("--seconds", type=int, required=True)
parser.add_argument("--pid", type=int, required=True)
args = parser.parse_args()
if args.seconds not in (10, 20, 30):
    parser.error("expected a finite 10, 20 or 30 second sample")
destination = Path(__file__).parent / (args.case + ".json")
if destination.exists():
    parser.error("refusing to overwrite an existing sample")
executable = "/private/tmp/sfv-viewport-retry-build/Build/Products/Debug/ScreenshotFromVideos.app/Contents/MacOS/ScreenshotFromVideos"

def ps(fields):
    return subprocess.check_output(
        ["/bin/ps", "-p", str(args.pid), "-o", fields], text=True
    ).strip()

identity = ps("lstart=,command=")
if not identity.endswith(executable):
    raise RuntimeError("target executable does not match final artifact")
digest = hashlib.sha256(Path(executable).read_bytes()).hexdigest()
record = dict(case=args.case, pid=args.pid, identity=identity, executable=executable,
              executable_sha256=digest,
              started_utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),
              effects="Read-only ps; no app input/startup/data mutation; evidence JSON only",
              samples=[], status="incomplete")
start = time.monotonic()
try:
    for index in range(args.seconds):
        time.sleep(max(0, start + index - time.monotonic()))
        if ps("lstart=,command=") != identity:
            raise RuntimeError("process identity changed")
        raw = ps("%cpu=,rss=,command=")
        cpu, rss, command = raw.split(maxsplit=2)
        if command != executable:
            raise RuntimeError("sample executable changed")
        record["samples"].append(dict(elapsed_s=round(time.monotonic()-start, 3),
                                      cpu_percent=float(cpu), rss_kib=int(rss), raw=raw))
    time.sleep(max(0, start + args.seconds - time.monotonic()))
    if ps("lstart=,command=") != identity:
        raise RuntimeError("process identity changed after sample")
    record.update(status="complete", duration_s=round(time.monotonic()-start, 3),
                  average_cpu_percent=statistics.mean(s["cpu_percent"] for s in record["samples"]),
                  minimum_cpu_percent=min(s["cpu_percent"] for s in record["samples"]),
                  maximum_cpu_percent=max(s["cpu_percent"] for s in record["samples"]),
                  peak_rss_kib=max(s["rss_kib"] for s in record["samples"]))
finally:
    destination.write_text(json.dumps(record, indent=2) + "\n")
print(json.dumps({k: v for k, v in record.items() if k != "samples"}, indent=2))
