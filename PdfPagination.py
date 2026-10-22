#!/usr/bin/env python3

# Shared by 12_ConvertTreesToFigures.py (called automatically there, on
# the cluster, as part of the normal step 12 run) and
# GenerateHighResTreePNGs.py (a manual, local-only tool - see that
# script's own header for why it's deliberately never auto-invoked).
# Factored out to a separate module so neither has to duplicate this
# logic or import the other (12_ConvertTreesToFigures.py is a large,
# non-library-style script, not meant to be imported from).

import fitz  # PyMuPDF

###############################################################################
# The full-detail tree PDF is one giant single page (ete3/Qt has no
# pagination of its own) - for a gene with thousands of leaves this is
# valid and has real searchable text (confirmed 2026-10-22), but slow
# for a PDF viewer to open/navigate: Okular took 16.4s just to rasterize
# a 24156-leaf, 9.25MB real example, and scrolling/zooming a single huge
# page is noticeably worse than flipping between pages.
#
# This slices that already-rendered PDF into a fixed number of pages as
# pure post-processing - no changes to ete3's own rendering, no need to
# re-run anything upstream. show_pdf_page(..., clip=...) copies the
# ORIGINAL page's real vector content for just that clipped region, so
# pagination does not rasterize anything or lose the real/searchable
# text. A fixed PAGE COUNT (not a fixed leaves-per-page) is used
# deliberately: tested both against a real 24156-leaf tree and a fixed,
# coarser page count (30) measured faster per-page load in both Okular
# and MuPDF than a finer one (162, approximating the same ~150
# leaves/page this pipeline's own pruning chunks use) - per-page load
# time turned out not to scale down with fewer leaves/page the way
# tested, so more pages was a pure loss, not a tradeoff.
#
# An alternative was tried and rejected 2026-10-22: rasterizing each
# paginated page to PNG (needed anyway for pdf2png()'s own existing
# >2-billion-pixel failure on one giant page - this DOES fix that, each
# page converts cleanly at a real, correctly-sized resolution instead of
# a degenerate 1x1 PNG) and then re-merging those 30 PNGs back into a
# single PDF. Real-world tested (not just measured): the merged file was
# 2.27 GB for the same 30-page, 24156-leaf tree, Okular was noticeably
# slower at high magnification than the vector version (expected -
# zooming a raster image means re-rendering a huge bitmap, not just
# re-scaling vector paths), and 600 DPI still wasn't even high enough
# resolution to be genuinely usable at that zoom level - fixing that
# would only make the file larger still. Not worth it: keep PDF pages as
# real vector content (this function) wherever possible - rasterizing
# (GenerateHighResTreePNGs.py, run by hand, locally, not here) is only
# for when a non-PDF image format is specifically needed, and even then
# stays local rather than landing in a git-tracked, cluster-synced
# directory - see that script's own header for the file-size/GitHub
# repo-limit reasoning.
def paginatePDF(pdfPath, numPages=30, outDir=None):
	# outDir=None (the default, used by every call in
	# 12_ConvertTreesToFigures.py) keeps the existing behavior: write
	# next to the input. GenerateHighResTreePNGs.py passes its own
	# --out-dir here instead, specifically so none of its output - not
	# even this intermediate paginated PDF - ever lands in the original,
	# git-tracked gene repo directory (see that script's own header for
	# why that matters).
	import os
	baseName = os.path.basename(pdfPath)
	paginatedName = baseName[:-4] + ".paginated.pdf" if baseName.endswith(".pdf") else baseName + ".paginated.pdf"
	paginatedPath = os.path.join(outDir, paginatedName) if outDir else os.path.join(os.path.dirname(pdfPath), paginatedName)
	src = fitz.open(pdfPath)
	page = src[0]
	rect = page.rect
	sliceHeight = rect.height / numPages

	out = fitz.open()
	for i in range(numPages):
		y0 = i * sliceHeight
		y1 = min((i + 1) * sliceHeight, rect.height)
		clip = fitz.Rect(rect.x0, y0, rect.x1, y1)
		newPage = out.new_page(width=rect.width, height=y1 - y0)
		newPage.show_pdf_page(newPage.rect, src, 0, clip=clip)

	out.save(paginatedPath)
	out.close()
	src.close()
	return paginatedPath
