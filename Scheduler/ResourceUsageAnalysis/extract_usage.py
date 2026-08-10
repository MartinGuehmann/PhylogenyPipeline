#!/usr/bin/env python3
"""Extract per-job resource usage (memory, walltime, input size) from a
gene repo's Logs/ directory into a CSV, for sizing Scheduler/Resources.cfg
from real cluster data instead of guessing. See README.md in this
directory for what this covers, what it doesn't, and hard-won gotchas
about the log format.
"""
import argparse
import re
import csv
from pathlib import Path

# sstat -j <id>.batch --format=JobID,MaxRSS,AveCPU,MaxVMSize -n
# line looks like: "8492254.bat+   1143628K   10:53:12   1227816K " normally,
# but AveCPU switches to Slurm's "D-HH:MM:SS" format once it exceeds 24h
# (e.g. "3-07:16:42") - confirmed 2026-08-10 this silently dropped every
# noTrimAl/BigTree0-scale row (exactly the multi-day CPU-time cases) from
# the dataset entirely, since the plain HH:MM:SS-only version of this
# regex just didn't match at all - not genuinely missing data, a bug.
SSTAT_RE = re.compile(r'^\S*\.bat\S*\s+(\d+)K\s+(?:(\d+)-)?(\d+):(\d+):(\d+)\s+(\d+)K', re.MULTILINE)

FILENAME_RE = re.compile(
    r'^(\d+)_(?:(\d+)_)?(09_Scheduler-AlignWith(\w+)\.sh|10_Scheduler(-Long)?-MakeTreeWithIQ-Tree\.sh)\.out$'
)

# e.g. ".../Alignments/FAMSA.noTrimAl/RogueIter_0/..." or ".../Alignments/MAGUS/BigTree0/..."
PATH_RE = re.compile(r'Alignments/([A-Za-z0-9]+)(\.[A-Za-z0-9_.]+)?/(?:RogueIter_(\d+)|BigTree\d+)')

REAL_TIME_RE = re.compile(r'^real\s+(\d+)m([\d.]+)s', re.MULTILINE)

RAXML_LOADED_RE = re.compile(r'Loaded alignment with (\d+) taxa and (\d+) sites')
IQTREE_ALN_RE = re.compile(r'Alignment has (\d+) sequences with (\d+) columns')

FAILURE_MARKERS = [
    "oom_kill", "CANCELLED", "command not found", "Failed to align",
    "MAX_N_PID exceded", "raxml-ng --check failed twice",
    "Killed", "core dumped", "Segmentation fault",
]


def parse_file(path: Path):
    fname_m = FILENAME_RE.match(path.name)
    if not fname_m:
        return None
    jobid, taskid, scriptname, alignerFromName, isLong = fname_m.groups()

    try:
        text = path.read_text(errors="replace")
    except Exception:
        return None

    # sstat logging itself was broken (bare $SLURM_JOB_ID instead of
    # $SLURM_JOB_ID.batch, silently returns nothing) until 2026-07-28
    # (commit 4752857) - any genuinely successful run older than that
    # has no memory/CPU telemetry at all. Don't require a match to keep
    # the row - keep it with these fields blank instead, so older
    # walltime-only data (still recoverable from `real`) isn't thrown
    # away along with the memory data that was never captured.
    maxrss_kb = maxvm_kb = ave_cpu_s = None
    m = SSTAT_RE.search(text)
    if m:
        maxrss_kb = int(m.group(1))
        days = int(m.group(2)) if m.group(2) else 0
        ave_cpu_s = days * 86400 + int(m.group(3)) * 3600 + int(m.group(4)) * 60 + int(m.group(5))
        maxvm_kb = int(m.group(6))

    if scriptname.startswith("09_"):
        step = "09_align"
    elif isLong:
        # 10_Scheduler-Long-MakeTreeWithIQ-Tree.sh gets 72h in
        # Resources.cfg (vs the regular script's 24h) - conflating the
        # two into one "10_tree" bucket made a genuinely-fine BigTree0
        # run (44.94h, comfortably under its real 72h budget) look like
        # a walltime crisis under the wrong 24h assumption. Keep these
        # separate - confirmed 2026-08-10 the hard way.
        step = "10_tree_long"
    else:
        step = "10_tree"
    aligner = alignerFromName if alignerFromName else None

    # .err often carries content .out doesn't (e.g. the alignment file
    # path with its .noTrimAl/.BigTree0-style suffix, for 09_ steps) -
    # load it up front so every extraction below can check both.
    errtext = ""
    errpath = path.with_suffix(".err")
    if errpath.exists():
        try:
            errtext = errpath.read_text(errors="replace")
        except Exception:
            pass

    pm = PATH_RE.search(text) or PATH_RE.search(errtext)
    suffix = ""
    if pm:
        if not aligner:
            aligner = pm.group(1)
        suffix = (pm.group(2) or "").lstrip(".")

    real_s = None
    rm = REAL_TIME_RE.search(text)
    if rm:
        real_s = int(rm.group(1)) * 60 + float(rm.group(2))

    taxa = sites = None
    rl = RAXML_LOADED_RE.search(text)
    if rl:
        taxa, sites = int(rl.group(1)), int(rl.group(2))
    else:
        il = IQTREE_ALN_RE.search(text)
        if il:
            taxa, sites = int(il.group(1)), int(il.group(2))

    if taxa is None and step == "09_align" and errtext:
        rl = RAXML_LOADED_RE.search(errtext)
        if rl:
            taxa, sites = int(rl.group(1)), int(rl.group(2))

    # bash's `time` keyword output for the aligner scripts lands in
    # .err, not .out (unlike sstat, which the wrapper explicitly
    # redirects into .out) - fall back to .err if not found in .out.
    if real_s is None and errtext:
        rm = REAL_TIME_RE.search(errtext)
        if rm:
            real_s = int(rm.group(1)) * 60 + float(rm.group(2))

    # A valid sstat line can still appear for a run that ultimately
    # failed/crashed (e.g. OOM-killed after already consuming a lot of
    # memory, or a raxml-ng-check failure) - that MaxRSS reflects "how
    # much it used before dying", not what a successful run needs, and
    # would badly skew any percentile/max-based sizing if left in.
    combined = text + errtext
    success = not any(marker in combined for marker in FAILURE_MARKERS)

    # For 09_align, "N. Align sequences with <Aligner>." is printed
    # unconditionally by RunAll.sh's own wrapper, whether or not the
    # aligner script itself actually ran (each 09_AlignWith<X>.sh skips
    # its own real work and returns immediately if $outFile already
    # exists - see e.g. 09_AlignWithRegTCoffee.sh). 09a_PostProcess-
    # Alignment.sh's raxml-ng --check always runs afterward regardless,
    # so a skip and a genuine run both produce a "successful" row with
    # real sstat/timing data - just for a few seconds of raxml-ng
    # validation instead of the actual alignment. Detected generically
    # (not per-aligner) by checking whether the aligner printed
    # anything of its own between the header line and raxml-ng's own
    # banner - confirmed against known skip/genuine RegTCoffee pairs.
    genuine_work = None
    if step == "09_align":
        hm = re.search(r'Align sequences with \w+\.\s*\n(.*?)(?:\n|$)', combined)
        if hm:
            next_nonblank = hm.group(1).strip()
            genuine_work = not next_nonblank.startswith("RAxML-NG")

    # Nothing useful to keep this row for at all - no memory, no
    # timing, no size, no genuine/skip determination.
    if maxrss_kb is None and real_s is None and taxa is None and genuine_work is None:
        return None

    return {
        "success": success,
        "genuine_work": genuine_work if genuine_work is not None else "",
        "file": path.name,
        "jobid": jobid,
        "taskid": taskid or "",
        "step": step,
        "aligner": aligner or "",
        "suffix": suffix,
        "taxa": taxa if taxa is not None else "",
        "sites": sites if sites is not None else "",
        "maxrss_kb": maxrss_kb if maxrss_kb is not None else "",
        "maxvm_kb": maxvm_kb if maxvm_kb is not None else "",
        "ave_cpu_s": ave_cpu_s if ave_cpu_s is not None else "",
        "real_s": real_s if real_s is not None else "",
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("logdir", type=Path, help="Gene repo's Logs/ directory, e.g. ../../Mas1/Logs")
    parser.add_argument("-o", "--out", type=Path, default=Path("usage.csv"), help="Output CSV path (default: usage.csv)")
    args = parser.parse_args()

    rows = []
    for path in sorted(args.logdir.glob("*.out")):
        row = parse_file(path)
        if row:
            rows.append(row)

    if not rows:
        print(f"No usable rows found under {args.logdir}")
        return

    print(f"parsed {len(rows)} usable rows out of scanned .out files")

    with args.out.open("w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        writer.writerows(rows)
    print(f"wrote {args.out}")


if __name__ == "__main__":
    main()
