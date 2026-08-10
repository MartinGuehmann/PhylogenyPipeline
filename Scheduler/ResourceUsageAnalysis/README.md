# Resource usage analysis

Extracts real per-job memory/walltime/input-size data from a gene repo's
`Logs/` directory, to size `Scheduler/Resources.cfg` from actual cluster
data instead of guessing. Built 2026-08-10 to answer a question that had
been deliberately deferred: `Resources.cfg`'s flat per-script CPU/mem/
walltime numbers don't generalize across workloads (trimAl vs noTrimAl,
aligner choice, BigTree-scale vs regular chunks) - see git history around
this date for the investigation this came out of.

## Usage

```
python3 extract_usage.py <path-to-gene-repo>/Logs -o usage.csv
python3 analyze_usage.py usage.csv
```

`extract_usage.py` walks every `*.out` file, pulls out `sstat`'s
MaxRSS/AveCPU/MaxVMSize (the wrapper scripts in `Scheduler/` log this at
the end of every job), wall-clock time from bash's `time` builtin,
sequence/site counts from raxml-ng's or IQ-Tree's own alignment-loading
messages, and the aligner + `.noTrimAl`/`.BigTree0`-style suffix from the
alignment file path mentioned in the log. `analyze_usage.py` groups the
result by (step, aligner, suffix) and prints median/p95/max.

## Gotchas found the hard way (2026-08-10)

These cost real back-and-forth to track down - read before trusting a
number out of this tool, or before "fixing" what looks like a bug in it:

- **`sstat` needs `$SLURM_JOB_ID.batch`, not bare `$SLURM_JOB_ID`.** The
  bare form silently returns nothing. Fixed in the wrapper scripts by
  commit `4752857` (2026-07-28) - any genuinely successful run *older*
  than that has no memory/CPU telemetry at all, even though the run
  itself was fine. `extract_usage.py` keeps such rows (with memory
  fields blank) rather than dropping them, since wall-clock time is
  often still recoverable.
- **`AveCPU` switches to `D-HH:MM:SS` past 24 CPU-hours** (e.g.
  `3-07:16:42`), not just `HH:MM:SS`. A regex that only expects the
  short form silently drops every row that exceeds it - which is
  exactly the noTrimAl/BigTree-scale rows you'd actually want to see.
- **A "successful" row can still be a skip, not real work.** Every
  `09_AlignWith<X>.sh` returns immediately if its output file already
  exists, but `09a_PostProcessAlignment.sh`'s raxml-ng `--check` always
  runs afterward regardless - so a skip and a genuine alignment run
  both produce a clean completion record, just for a few seconds of
  validation instead of the real work. `genuine_work` (09_align rows
  only) detects this by checking whether the aligner printed anything
  of its own between the "N. Align sequences with X." header and
  raxml-ng's own banner - a skip goes straight to the banner, a real
  run doesn't. Always filter on this for step 9, not just `success`.
- **`10_Scheduler-Long-MakeTreeWithIQ-Tree.sh` (72h budget) and
  `10_Scheduler-MakeTreeWithIQ-Tree.sh` (24h budget) are different
  scripts with different walltime budgets** - conflating them into one
  bucket made a genuinely-fine 44.94h BigTree0 run look like a walltime
  crisis under the wrong 24h assumption. Kept as separate `step` values
  (`10_tree` vs `10_tree_long`) for exactly this reason.
- **`sstat`-bearing "success" rows can still be failure-mode
  measurements** - a job OOM-killed after already consuming 90+GB still
  produces a valid `sstat` line, reflecting "how much before dying," not
  genuine steady-state need. Filtered via `success` (checks for
  `oom_kill`, `CANCELLED`, `command not found`, etc. anywhere in the
  combined `.out`+`.err` text) - always filter on this too, it's not
  automatic.
- **Timing/size data splits unpredictably between `.out` and `.err`**
  depending on how each wrapper script redirects things (`sstat`'s own
  `2>&1 >&2` merges everything into `.out`; bash's `time` output and
  raxml-ng's `Loaded alignment with N taxa` line for 09_align steps
  usually land in `.err` instead). `extract_usage.py` already checks
  both for everything it extracts - if adding a new field, check both
  files, don't assume one.

## What's actually been found so far (2026-08-10, Mas1)

- Real memory usage is a small fraction of `Resources.cfg`'s allocated
  amounts almost everywhere checked (e.g. RegTCoffee: 100GB allocated,
  under 1GB actually used; step 10: 32GB allocated, ~1.1-1.4GB actually
  used for regular chunks). Right-sizing memory down looks like a safe,
  well-supported change.
- FAMSA scales very well to BigTree0/BigTree5 size (tens of thousands of
  taxa) - both memory and walltime scale sub-linearly with sequence
  count, no cliff.
- `noTrimAl` tree-building (the *regular* 24h script, not the Long one -
  noTrimAl was never meant to run at BigTree scale) is the real
  walltime risk: untrimmed alignments have far more sites/columns (seen
  up to ~20x more for MAGUS), and IQ-Tree's walltime scales
  sub-linearly but still substantially with site count - FAMSA.noTrimAl
  and MAGUS.noTrimAl both land within a couple hours of the 24h
  ceiling, which is almost certainly what actually caused the
  checkpoint-resume incidents on record, not BigTree-scale runs (those
  are correctly routed through the 72h Long script and comfortably fit).
- Several aligners (ClustalO, MAFFT, MUSCLE, MUSCLE5, SUPER5) still have
  thin or zero genuine-work + memory-telemetry samples for step 9 -
  either genuinely under-exercised, or their real runs predate the
  2026-07-28 `sstat` fix and simply have no memory data to recover.
