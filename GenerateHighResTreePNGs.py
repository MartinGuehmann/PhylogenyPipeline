#!/usr/bin/env python3

# Deliberately NOT called by any Scheduler/step script - this is a
# manual, local-only tool, never invoked automatically by step 12 or
# any other part of the cluster-run pipeline. Run it by hand, locally,
# only when you actually want to look at a specific tree's PNGs.
#
# Why this is local-only, not part of the automatic pipeline: every
# gene repo auto-commits its own output (CommitOutputInBatches.sh), and
# there are 8 gene repos, each with multiple rounds/aligners/comparison
# trees - a PNG set at a resolution high enough to actually be useful
# (confirmed 2026-10-22: ~221MB estimated for one 24156-leaf tree's 30
# pages at 1200 DPI) adds up fast against GitHub's 10GB-per-repo limit
# if generated automatically for every tree on the cluster. Keeping
# generation manual and local means it only happens for the specific
# tree you're actually looking at right now, and the files never get
# near a git commit at all - not even a question of remembering to
# .gitignore them.
#
# Paginates a full-detail tree PDF (the same way
# 12_ConvertTreesToFigures.py's own paginatePDF() does, reusing that
# exact function from PdfPagination.py) and rasterizes each page to a
# separate PNG at a given DPI via pdftoppm. Does NOT attempt to also
# merge those PNGs back into one file - that was tried and rejected
# (see PdfPagination.py's own header comment for the real numbers: a
# 2.27GB merged PDF, still not even high enough resolution to be
# genuinely usable at that size).
#
# Usage:
#   python3 GenerateHighResTreePNGs.py <fullTree.pdf> [--pages N] [--dpi N] [--out-dir DIR]
#
# Defaults: --pages 30 (matching paginatePDF()'s own default, already
# confirmed to behave better than a finer page count - see
# PdfPagination.py), --dpi 1200 (confirmed 2026-10-22: legible at this
# resolution, unlike the pipeline's own default 600 DPI which was
# borderline), --out-dir alongside the input PDF.

import argparse
import os
import subprocess
import sys

from PdfPagination import paginatePDF


def main():
	parser = argparse.ArgumentParser(description=__doc__)
	parser.add_argument("pdf", help="Path to a full-detail tree PDF (e.g. a *.fullTree.pdf)")
	parser.add_argument("--pages", type=int, default=30, help="Number of pages to paginate into (default: 30)")
	parser.add_argument("--dpi", type=int, default=1200, help="Resolution for the PNG conversion (default: 1200)")
	parser.add_argument("--out-dir", default=None, help="Directory for the output PNGs (default: alongside the input PDF)")
	args = parser.parse_args()

	if not os.path.isfile(args.pdf):
		print(f"No such file: {args.pdf}", file=sys.stderr)
		sys.exit(1)

	outDir = args.out_dir or os.path.dirname(os.path.abspath(args.pdf)) or "."
	os.makedirs(outDir, exist_ok=True)

	print(f"Paginating {args.pdf} into {args.pages} pages...")
	# outDir explicitly passed here (not the default) - everything this
	# tool produces, including this intermediate paginated PDF, stays in
	# --out-dir, never next to the original input (which usually lives
	# in a real, git-tracked gene repo directory). See this script's own
	# header for why that matters.
	paginatedPath = paginatePDF(args.pdf, numPages=args.pages, outDir=outDir)
	print(f"Wrote {paginatedPath}")

	baseName = os.path.splitext(os.path.basename(paginatedPath))[0]
	outPrefix = os.path.join(outDir, baseName)
	print(f"Rasterizing {args.pages} pages at {args.dpi} DPI (this is the slow step - "
	      f"expect roughly 10-20s/page at 1200 DPI, confirmed 2026-10-22)...")
	subprocess.run(["pdftoppm", "-png", "-r", str(args.dpi), paginatedPath, outPrefix], check=True)

	pngCount = len([f for f in os.listdir(outDir) if f.startswith(os.path.basename(outPrefix)) and f.endswith(".png")])
	print(f"Wrote {pngCount} PNGs to {outDir}/{os.path.basename(outPrefix)}-*.png")


if __name__ == "__main__":
	main()
