#!/usr/bin/env python3
"""Summarize usage.csv (from extract_usage.py) into per-(step, aligner,
suffix) resource statistics - median/p95/max memory and walltime, plus
the taxa-count range each group covers. See README.md in this directory
for how to read this table and what the important caveats are.
"""
import argparse
import csv
from collections import defaultdict
from pathlib import Path
from statistics import median


def to_num(v):
    return float(v) if v not in ("", None) else None


def pct(values, p):
    s = sorted(values)
    if not s:
        return None
    k = (len(s) - 1) * p
    f = int(k)
    c = min(f + 1, len(s) - 1)
    if f == c:
        return s[f]
    return s[f] + (s[c] - s[f]) * (k - f)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("csv", type=Path, nargs="?", default=Path("usage.csv"), help="CSV from extract_usage.py (default: usage.csv)")
    args = parser.parse_args()

    rows = [
        r for r in csv.DictReader(args.csv.open())
        if r["success"] == "True"
        # For 09_align, exclude skip-only reruns (aligner didn't actually
        # run, only raxml-ng's post-check did - see extract_usage.py's
        # own comment). Step 10 rows are inherently genuine: taxa/sites
        # only ever get populated from IQ-Tree's own "Alignment has..."
        # line, which can't appear unless IQ-Tree genuinely ran.
        and (r["step"] != "09_align" or r["genuine_work"] == "True")
    ]

    groups = defaultdict(list)
    for r in rows:
        key = (r["step"], r["aligner"], r["suffix"])
        groups[key].append(r)

    print(f"{'step':13} {'aligner':12} {'suffix':10} {'n':>4} {'RSS_med_GB':>11} {'RSS_p95_GB':>11} {'RSS_max_GB':>11} {'wall_med_h':>10} {'wall_max_h':>10} {'taxa_range':>14}")
    for key in sorted(groups.keys()):
        step, aligner, suffix = key
        grp = groups[key]
        rss_gb = [to_num(r["maxrss_kb"]) / 1024 / 1024 for r in grp if to_num(r["maxrss_kb"]) is not None]
        walls_h = [to_num(r["real_s"]) / 3600 for r in grp if to_num(r["real_s"]) is not None]
        ave_cpu_h = [to_num(r["ave_cpu_s"]) / 3600 for r in grp if to_num(r["ave_cpu_s"]) is not None]
        taxa = [to_num(r["taxa"]) for r in grp if to_num(r["taxa"]) is not None]
        taxa_range = f"{int(min(taxa))}-{int(max(taxa))}" if taxa else "n/a"

        wall_med = median(walls_h) if walls_h else None
        wall_max = max(walls_h) if walls_h else None
        # No `real` wall-clock captured for this group - AveCPU (thread-summed, not wall-clock) as a rough fallback note
        wall_med_s = f"{wall_med:.2f}" if wall_med is not None else ("cpu:" + f"{median(ave_cpu_h):.1f}" if ave_cpu_h else "n/a")
        wall_max_s = f"{wall_max:.2f}" if wall_max is not None else ("cpu:" + f"{max(ave_cpu_h):.1f}" if ave_cpu_h else "n/a")

        rss_med_s = f"{median(rss_gb):.2f}" if rss_gb else "n/a"
        rss_p95_s = f"{pct(rss_gb, 0.95):.2f}" if rss_gb else "n/a"
        rss_max_s = f"{max(rss_gb):.2f}" if rss_gb else "n/a"

        print(f"{step:13} {aligner:12} {suffix:10} {len(grp):4} {rss_med_s:>11} {rss_p95_s:>11} {rss_max_s:>11} {wall_med_s:>10} {wall_max_s:>10} {taxa_range:>14}")


if __name__ == "__main__":
    main()
