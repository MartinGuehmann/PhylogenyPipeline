#!/bin/python3

from ete3 import Tree, NexmlTree, nexml, faces, AttrFace, TextFace, RectFace, SeqMotifFace, PieChartFace, TreeStyle, NodeStyle
import csv
from inspect import getmembers
from Bio import AlignIO, Align

import os # Strip extension from file
import sys, getopt # Parse program arguments

# Sequence logo
import numpy as np
import pandas as pd
import matplotlib.pyplot as plt
import matplotlib.colors as mcolors
import logomaker as logomaker

# Debugging
import logging
# This also activates debugging in matplotlib
#logging.basicConfig(level=logging.DEBUG)

lineWidth = 4
margin = 4 / 2
nodeShapeSize = lineWidth - 1

# If you add more levels add to the last
SHaLRTThresholds = [80.0, 75.0, 70.0]
aBayesThresholds = [95.0, 90.0, 85.0]
UFBootThresholds = [95,   90,   85  ]

# If you add more levels add before the last entry
# Collorful pallete for support values
#colorThresholds = ["Green", "Yellow", "Orange", "Red", "Black"]
# Simplified black and grey pallete for support values
colorThresholds = ["Black", "DarkGrey", "DarkGrey", "DarkGrey", "LightGrey"]

type_regular  = 0
type_legend   = 1
type_title    = 2
type_total    = 3
type_ingroup  = 4
type_outgroup = 5
type_unknown  = 6

# Global maps
aminoAcidColorMap       = {}
aminoAcidTreeColorMap   = {}
taxonColorMap           = {}
genusInterestingTaxaMap = {}

###############################################################################
class ColorData:
	def __init__(self, color, entryType, rank):
		self.color     = color
		self.entryType = entryType
		self.rank      = rank
	def getRGBColor(self):
		return mcolors.CSS4_COLORS[self.color.lower()]

###############################################################################
class Clade:
	def __init__(self, typeSeqID, name, forgroundColor, backgroundColor, typeNode):
		self.typeSeqID       = typeSeqID
		self.name            = name
		self.forgroundColor  = forgroundColor
		self.backgroundColor = backgroundColor
		self.typeNode        = typeNode
		self.rootNode        = None

###############################################################################
class ConfigData:
	def __init__(self, configFileName):
		self.refSeqFileName              = ""
		self.refSequence                 = None
		self.refAlignment                = None
		self.refRecord                   = None
		self.specialAminoAcidPos         = -1
		self.specialAminoAcidPosInAln    = -1
		self.toLowerLimit                = -1
		self.toUpperLimit                = -1
		self.interestingAAPositions      = []
		self.interestingAAPositionsInAln = []
		self.aaToHighlight               = []
		self.aaToHighlightInAln          = []
		self.highlightColors             = []
		self.alignmentData               = None

		try:
			with open(configFileName, newline='') as configFile:

				configFileBase = os.path.dirname(configFileName)
				configReader = csv.reader(configFile, delimiter='\t')
				for row in configReader:
					# Continue if the line is empty
					if not row:
						continue
					if row[0][0] == '#':
						continue

					if len(row) > 1:
						if row[0].lower() == "seqfile":
							self.refSeqFileName = os.path.join(configFileBase, row[1]) # This is still not windows compatible, because the path is given with the Linux file separator
						elif row[0].lower() == "aapos":
							self.specialAminoAcidPos = int(row[1])
						elif row[0].lower() == "tolowerlimit":
							self.toLowerLimit = int(row[1])
						elif row[0].lower() == "toupperlimit":
							self.toUpperLimit = int(row[1])
						elif row[0].lower() == "interestingaapositions":
							i = 1
							while i < len(row):
								self.interestingAAPositions.append(int(row[i]))
								i += 1

						elif row[0].lower() == "aatohighlight":
							i = 1
							while i < len(row):
								self.aaToHighlight.append(int(row[i]))
								i += 1

						elif row[0].lower() == "highlightcolors":
							i = 1
							while i < len(row):
								self.highlightColors.append(row[i])
								i += 1
		except FileNotFoundError as err:
			print(err)
			print("This might be intended if you want to run without marking special amino acids")
			pass

	def setAlignmentData(self, alignmentData):
		self.alignmentData = alignmentData
		self.refSequence = AlignIO.read(self.refSeqFileName, "fasta")

		for record in self.alignmentData.masterAlignment:
			if self.refSequence[0].id in record.id:

				gapFreeRecord = record.seq.ungap()
				aligner = Align.PairwiseAligner()
				aligner.mode = 'global'
				self.refAlignment = aligner.align(self.refSequence[0].seq, gapFreeRecord)
				self.refRecord = record
				break

		self.specialAminoAcidPosInAln = self.getPosInRefAlignment(self.specialAminoAcidPos)

		for pos in self.interestingAAPositions:
			posInAln = self.getPosInRefAlignment(pos)
			self.interestingAAPositionsInAln.append(posInAln)

		for pos in self.aaToHighlight:
			posInAln = self.getPosInRefAlignment(pos)
			self.aaToHighlightInAln.append(posInAln)

	def getPosInRefAlignment(self, pos):
		lastPos = 0
		thisPos = 0
		numGaps = 0
		for pair in self.refAlignment[0].aligned[0]:
			thisPos  = pair[0]
			numGaps += thisPos - lastPos
			lastPos  = pair[1]
			if lastPos > pos:
				break

		i = 0
		aaIndex = numGaps + 1 # This is zero indexed but pos is one indexed, so add one to account for that
		while i < len(self.refRecord):
			if self.refRecord[i] == "-":
				i += 1
				continue

			if aaIndex == pos:
				return i

			aaIndex += 1
			i += 1

		return -1

	def getAlignmentLength(self):
		return self.alignmentData.masterAlignment.get_alignment_length()

###############################################################################
class AlignmentData:
	def __init__(self, cladeTreeFile):
		isFullTree = (cladeTreeFile == "")

		if isFullTree:
			alnFile = os.path.splitext(inputTree)[0]
		else:
			alnFile = os.path.splitext(os.path.splitext(os.path.splitext(cladeTreeFile)[0])[0])[0]

		self.masterAlignment = AlignIO.read(alnFile, "phylip-relaxed")

###############################################################################
def hasSpecialAA():
	return len(aminoAcidTreeColorMap) > 0

###############################################################################
def hasTaxa():
	return len(taxonColorMap) > 0

###############################################################################
def countAttributes(tree, attribute):

	countMap = {}
	numLeaves = 0
	for leaf in tree.iter_leaves():
		if hasattr(leaf, attribute):
			key = getattr(leaf, attribute)
			if key in countMap:
				countMap[key] += 1
			else:
				countMap[key] = 1
		else:
			if "_" in countMap:
				countMap["_"] += 1
			else:
				countMap["_"] = 1

		numLeaves += 1

	return countMap, numLeaves

###############################################################################
def getColorsAndPercents(tree, colorMap, attribute):

	countMap, numLeaves = countAttributes(tree, attribute)

	percents = []
	colors   = []
	for key, value in countMap.items():
		percents.append((value / numLeaves) * 100)
		if key in colorMap:
			colors.append(colorMap[key].color)
		else:
			colors.append("Black")

	return percents, colors

###############################################################################
def getSortedClades(tree, clades):
	cladeMap = {}
	for clade in clades:
		cladeMap[clade.name] = clade

	sortedClades = []
	for leaf in tree.iter_leaves():
		if leaf.cladeName != "":
			sortedClades.append(cladeMap[leaf.cladeName])

	return sortedClades

###############################################################################
def getAminoAcidColorScheme():
	colorScheme = {}
	for aa, color in aminoAcidColorMap.items():
		colorScheme[aa] = color.getRGBColor()

	return colorScheme

###############################################################################
def makeSeqLogo(tree, clades, refSeqConfigData, logoOutFileBase):

	spacing = 5
	minPos = refSeqConfigData.specialAminoAcidPos - refSeqConfigData.toLowerLimit
	maxPos = refSeqConfigData.specialAminoAcidPos + refSeqConfigData.toUpperLimit
	anchor = spacing - (minPos % spacing)
	seqRange = list(range(minPos + anchor, maxPos, spacing))

	if refSeqConfigData.specialAminoAcidPosInAln < 0:
		return

	lowerLimit = refSeqConfigData.specialAminoAcidPosInAln - refSeqConfigData.toLowerLimit
	if lowerLimit < 0:
		lowerLimit = 0

	upperLimit = refSeqConfigData.specialAminoAcidPosInAln + refSeqConfigData.toUpperLimit
	if upperLimit >= refSeqConfigData.getAlignmentLength():
		upperLimit = refSeqConfigData.getAlignmentLength() -1

	rowHeight = 0.3
	colWidth  = 0.3
	colSpan1 = 1
	colSpan2 = 5
	colSpan3 = 2

	numLogoChars = upperLimit - lowerLimit

	colSpans = [colSpan1, colSpan2, colSpan3, numLogoChars]
	numCols = sum(colSpans)

	numClades = len(clades)

	# Make figure
	logoFigure = plt.figure(figsize=[colWidth * numCols, rowHeight * numClades])

	sequenceMap = {}
	for record in refSeqConfigData.alignmentData.masterAlignment:
		sequenceMap[record.id] = record

	colorScheme = getAminoAcidColorScheme()
	sortedClades = getSortedClades(tree, clades)
	i = 0
	for clade in sortedClades:

		sequences = []
		numSeqs = 0
		for leaf in clade.rootNode.iter_leaves():
			if leaf.name in sequenceMap:
				record = sequenceMap[leaf.name]
				sequences.append(str(record.seq[lowerLimit:upperLimit]))
				numSeqs += 1

		print("Make " + str(i+1) + ". of " + str(numClades) + " SeqLogos for the clade " + clade.name, file=sys.stderr)

		# Print the clade number onto the figure
		itemNum = 0
		colNum = sum(colSpans[:itemNum])
		cladeInfo = f"{i+1:5}"

		ax = plt.subplot2grid((numClades, numCols), (i, colNum), colspan=colSpans[itemNum])
		ax.text(1.0, 0.5, cladeInfo, va="center_baseline", ha="right")
		ax.tick_params(labelbottom=False, labelleft=False)
		ax.set_frame_on(False)
		ax.set_yticks([])
		ax.set_xticks([])

		# Print the clade name onto the figure
		itemNum += 1
		colNum = sum(colSpans[:itemNum])
		cladeInfo = f"{clade.name}"

		ax = plt.subplot2grid((numClades, numCols), (i, colNum), colspan=colSpans[itemNum])
		ax.text(0.05, 0.5, cladeInfo, va="center_baseline", ha="left")
		ax.tick_params(labelbottom=False, labelleft=False)
		ax.set_frame_on(False)
		ax.set_yticks([])
		ax.set_xticks([])

		# Print the number of sequences in the clade onto the figure
		itemNum += 1
		colNum = sum(colSpans[:itemNum])
		cladeInfo = f"{numSeqs:8}"

		ax = plt.subplot2grid((numClades, numCols), (i, colNum), colspan=colSpans[itemNum])
		ax.text(1.0, 0.5, cladeInfo, va="center_baseline", ha="right")
		ax.tick_params(labelbottom=False, labelleft=False)
		ax.set_frame_on(False)
		ax.set_yticks([])
		ax.set_xticks([])

		# Print the sequence logo onto the figure
		itemNum += 1
		colNum = sum(colSpans[:itemNum])
		ax = plt.subplot2grid((numClades, numCols), (i, colNum), colspan=colSpans[itemNum])
		ax.set_yticks([])
		if clade != sortedClades[-1]:
			ax.set_xticks([])

		try:
			dataMatrix = logomaker.alignment_to_matrix(sequences)
			seqLogo = logomaker.Logo(dataMatrix, ax=ax, color_scheme=colorScheme)

			j = 0
			for pos in refSeqConfigData.aaToHighlight:
				pos -= minPos
				seqLogo.highlight_position(p=pos, color=refSeqConfigData.highlightColors[j], alpha=.5)
				if j < len(refSeqConfigData.highlightColors) - 1:
					j += 1


			if clade == sortedClades[-1]:
				seqLogo.style_xticks(anchor=anchor, spacing=spacing)
				ax.set_xticklabels('%d'%x for x in seqRange)
		# It should be something like this, but it is not imported with logomaker
#		except logomaker.LogomakerError as err:
		except Exception as err:
			# We can simply continue here, only the sequence logo has missing entries
			# The trees should not be affected
			print(err)
			pass

		i += 1

	logoFigure.savefig(logoOutFileBase + ".logo.pdf", format='pdf')
	logoFigure.savefig(logoOutFileBase + ".logo.svg", format='svg')

	numLogoChars = len(refSeqConfigData.interestingAAPositions)

	colSpans = [colSpan1, colSpan2, colSpan3, numLogoChars]
	numCols = sum(colSpans)

	numClades = len(clades)

	# Make figure
	logoFigure = plt.figure(figsize=[colWidth * numCols, rowHeight * numClades])

	# ToDo: Copied code, merge common parts of the copy
	i = 0
	for clade in sortedClades:

		sequences = []
		numSeqs = 0
		for leaf in clade.rootNode.iter_leaves():
			if leaf.name in sequenceMap:
				record = sequenceMap[leaf.name]
				seq = ''.join([ record.seq[i] for i in refSeqConfigData.interestingAAPositionsInAln])
				sequences.append(seq)
				numSeqs += 1

		print("Make " + str(i+1) + ". of " + str(numClades) + " SingleSeqLogos for the clade " + clade.name, file=sys.stderr)

		# Print the clade number onto the figure
		itemNum = 0
		colNum = sum(colSpans[:itemNum])
		cladeInfo = f"{i+1:5}"

		ax = plt.subplot2grid((numClades, numCols), (i, colNum), colspan=colSpans[itemNum])
		ax.text(1.0, 0.5, cladeInfo, va="center_baseline", ha="right")
		ax.tick_params(labelbottom=False, labelleft=False)
		ax.set_frame_on(False)
		ax.set_yticks([])
		ax.set_xticks([])

		# Print the clade name onto the figure
		itemNum += 1
		colNum = sum(colSpans[:itemNum])
		cladeInfo = f"{clade.name}"

		ax = plt.subplot2grid((numClades, numCols), (i, colNum), colspan=colSpans[itemNum])
		ax.text(0.05, 0.5, cladeInfo, va="center_baseline", ha="left")
		ax.tick_params(labelbottom=False, labelleft=False)
		ax.set_frame_on(False)
		ax.set_yticks([])
		ax.set_xticks([])

		# Print the number of sequences in the clade onto the figure
		itemNum += 1
		colNum = sum(colSpans[:itemNum])
		cladeInfo = f"{numSeqs:8}"

		ax = plt.subplot2grid((numClades, numCols), (i, colNum), colspan=colSpans[itemNum])
		ax.text(1.0, 0.5, cladeInfo, va="center_baseline", ha="right")
		ax.tick_params(labelbottom=False, labelleft=False)
		ax.set_frame_on(False)
		ax.set_yticks([])
		ax.set_xticks([])

		# Print the sequence logo onto the figure
		itemNum += 1
		colNum = sum(colSpans[:itemNum])
		ax = plt.subplot2grid((numClades, numCols), (i, colNum), colspan=colSpans[itemNum])
		ax.set_yticks([])
		if clade != sortedClades[-1]:
			ax.set_xticks([])

		try:
			dataMatrix = logomaker.alignment_to_matrix(sequences)
			seqLogo = logomaker.Logo(dataMatrix, ax=ax, color_scheme=colorScheme)
			if clade == sortedClades[-1]:
				seqLogo.style_xticks(anchor=0, spacing=1, rotation=270)
#				ax.set_xticklabels('%d'%x for x in seqRange)
				ax.set_xticklabels(refSeqConfigData.interestingAAPositions)
		# It should be something like this, but it is not imported with logomaker
#		except logomaker.LogomakerError as err:
		except Exception as err:
			# We can simply continue here, only the sequence logo has missing entries
			# The trees should not be affected
			print(err)
			pass

		i += 1

	logoFigure.savefig(logoOutFileBase + ".logoSingle.pdf", format='pdf')
	logoFigure.savefig(logoOutFileBase + ".logoSingle.svg", format='svg')

###############################################################################
def sortMasterAlignment(tree, alignmentData, sortedAlignmentFile):

	sequenceMap = {}
	for record in alignmentData.masterAlignment:
		sequenceMap[record.id] = record

	with open(sortedAlignmentFile, "w") as outFile:
		for leaf in tree.iter_leaves():
			if leaf.name != "" and leaf.name in sequenceMap:
				outFile.write(">" + leaf.name + "\n")
				outFile.write(str(sequenceMap[leaf.name].seq) + "\n")


###############################################################################
def determineSpecialAminoAcidsAtPos(tree, refSeqConfigData):

	if refSeqConfigData.specialAminoAcidPosInAln < 0:
		return

	sequenceMap = {}
	for record in refSeqConfigData.alignmentData.masterAlignment:
		sequenceMap[record.id] = record

	for leaf in tree.iter_leaves():
		if leaf.name in sequenceMap:
			record = sequenceMap[leaf.name]
			leaf.specialAA = record[refSeqConfigData.specialAminoAcidPosInAln].upper()

###############################################################################
def loadColorMap(colorFile, colorMap):
	with open(colorFile, newline='') as colorMapFile:
		colorReader = csv.reader(colorMapFile, delimiter='\t')
		for row in colorReader:
			# Continue if the line is empty
			if not row:
				continue
			if row[0][0] == '#':
				continue

			key = row[0]
			color = row[1]
			entryType = type_regular
			if len(row) > 2:
				if row[2].lower() == "regular":
					entryType = type_regular
				if row[2].lower() == "legendonly":
					entryType = type_legend
				if row[2].lower() == "title":
					entryType = type_title
				if row[2].lower() == "total":
					entryType = type_total
				if row[2].lower() == "ingroup":
					entryType = type_ingroup
				if row[2].lower() == "outgroup":
					entryType = type_outgroup
				if row[2].lower() == "unknown":
					entryType = type_unknown

			if len(row) > 3:
				rank = int(row[3])
			else:
				rank = 0

			colorMap[key] = ColorData(color, entryType, rank)

		colorMap["_"] = ColorData("Black", type_regular, 0)

###############################################################################
def countLeaves(tree):
	numLeaves = 0
	for leaf in tree.iter_leaves():
		numLeaves += 1

	return numLeaves

###############################################################################
def getSupportOverThresholdColor(supports):
	supportValues = supports.split("/")
	if len(supportValues) > 2:
		try:
			if(float(supportValues[0])         >= SHaLRTThresholds[0] and
			   float(supportValues[1]) * 100.0 >= aBayesThresholds[0] and
			     int(supportValues[2])         >= UFBootThresholds[0]):
				return 'Black'
		except ValueError:
			pass
	else:
		try:
			if(  int(supportValues[0]) > UFBootThresholds[0]):
				return 'Black'
		except ValueError:
			pass

	return 'Gray'

###############################################################################
def addSupportPieCharts(node, columnNum):
	supports = node.name
	supportValues = supports.split("/")

	if len(supportValues) > 2:
		try:
			SHaLRTValue = float(supportValues[0])
			aBayesValue = float(supportValues[1]) * 100
			UFBootValue =   int(supportValues[2])

			columnNum = addOneSupportPieChart(node, columnNum, SHaLRTValue, SHaLRTThresholds)
			columnNum = addOneSupportPieChart(node, columnNum, aBayesValue, aBayesThresholds)
			columnNum = addOneSupportPieChart(node, columnNum, UFBootValue, UFBootThresholds)

			return columnNum

		except ValueError:
			pass
	elif len(supportValues) > 0:
		try:
			UFBootValue = int(supportValues[0])
			return addOneSupportPieChart(node, columnNum, UFBootValue, UFBootThresholds)
		except ValueError:
			pass

	return 0

###############################################################################
def addOneSupportPieChart(node, columnNum, value, thresholds):

	if   value >= thresholds[0]:
		color = colorThresholds[0]
	elif value >= thresholds[1]:
		color = colorThresholds[1]
	elif value >= thresholds[2]:
		color = colorThresholds[2]
	else:
		color = colorThresholds[3]

	colorEmpty = colorThresholds[-1]

	percents = [value, 100.0 - value]
	colors   = [color, colorEmpty]

	pie_face = PieChartFace(percents, 10, 10, colors)
	node.add_face(pie_face, column=columnNum, position="branch-right")
	columnNum += 1
	return columnNum

###############################################################################
def fullTreeLayout(node):
	if node.is_leaf():

		columnNum = 0
		if hasSpecialAA():
			if hasattr(node, 'specialAA'):
				aa_face = TextFace(node.specialAA)
				aa_face.background.color = aminoAcidTreeColorMap[node.specialAA].color
			else:
				aa_face = TextFace(" ")
				aa_face.background.color = "Black"

			aa_face.margin_top = 2
			aa_face.margin_bottom = 2
			node.add_face(aa_face, column=columnNum, position="aligned")
			columnNum += 1

		if hasTaxa():
			if hasattr(node, 'taxonOfInterest'):
				it_face = TextFace(" " + node.taxonOfInterest + " ")
				it_face.fgcolor = taxonColorMap[node.taxonOfInterest].color
			else:
				it_face = TextFace(" Unidentified ")
				it_face.fgcolor = "Black"

			it_face.margin_top = 2
			it_face.margin_bottom = 2
			node.add_face(it_face, column=columnNum, position="aligned")
			columnNum += 1

		# If terminal node, draw its name
		if node.name == "":
			name_face = TextFace(" ")
		else:
			name_face = AttrFace("name", text_prefix=" ")

		if hasattr(node.img_style, 'faces_bgcolor'):
			name_face.background.color = node.img_style.faces_bgcolor
			name_face.margin_top = 2
			name_face.margin_bottom = 2
		# Add the name face to the image at the preferred position
		node.add_face(name_face, column=columnNum, position="aligned")
		columnNum += 1

		rect_face = TextFace("                                            ")
		rect_face.background.color = node.img_style["fgcolor"]
		rect_face.margin_top = 2
		rect_face.margin_bottom = 2
		node.add_face(rect_face, column=columnNum, position="aligned")
		columnNum += 1
		if node.cladeName != "":
			clade_face = TextFace(node.cladeName, fsize=100)
			node.add_face(clade_face, column=columnNum, position="float-right")
			columnNum += 1

	else:
		addSupportValues(node)

###############################################################################
def collapsedTreeLayout(node):
	# alinged makes some trouble with single branches
	pos = "branch-right"
	if node.is_leaf():
		collapsedLeafLayout(node, pos)
	elif not node.img_style["draw_descendants"]:
		# Technically this is an internal node
		addSupportValues(node)
		collapsedNodeLayout(node, 0, -2, pos)
	else:
		addSupportValues(node)

###############################################################################
def collapsedCompactTreeLayout(node):
	pos = "branch-right"
	if node.is_leaf():
		columnNum = 0

		rectFace = RectFace(lineWidth, lineWidth, "White", "White")
		rectFace.margin_top    = margin
		rectFace.margin_bottom = margin
		node.add_face(rectFace, column=columnNum, position=pos)
	elif not node.img_style["draw_descendants"]:
		# Technically this is an internal node
		columnNum = addSupportPieCharts(node, 0)
		collapsedNodeLayout(node, columnNum, 0, pos)
	else:
		columnNum = addSupportPieCharts(node, 0)

###############################################################################
def noTreeLayout(node):
	pass

###############################################################################
def collapsedSimpleTreeLayout(node):
	pos = "branch-right"

	if node.is_leaf():
		columnNum = 0

		name_face =  TextFace(" ")
		name_face.margin_top = -2
		# Add the name face to the image at the preferred position
		node.add_face(name_face, column=columnNum, position=pos)
	elif not node.img_style["draw_descendants"]:
		# Technically this is an internal node
		columnNum = addSupportPieCharts(node, 0)
		collapsedSimpleNodeLayout(node, columnNum, 0, False, pos)
	else:
		columnNum = addSupportPieCharts(node, 0)

###############################################################################
def collapsedSimpleNoSupportTreeLayout(node):
	pos = "branch-right"

	if node.is_leaf():
		columnNum = 0

		name_face =  TextFace(" ")
		name_face.margin_top = -2
		# Add the name face to the image at the preferred position
		node.add_face(name_face, column=columnNum, position=pos)
	elif not node.img_style["draw_descendants"]:
		# Technically this is an internal node
		columnNum = 0
		collapsedSimpleNodeLayout(node, columnNum, 0, False, pos)

###############################################################################
def collapsedLeafLayout(node, pos):
	columnNum = 0

	# If terminal node, draws it name
	if node.name == "":
		name_face =  TextFace(" ")
	else:
		name_face = AttrFace("name", text_prefix=" ", text_suffix=" ")

	name_face.margin_top = -2
	# Add the name face to the image at the preferred position
	node.add_face(name_face, column=columnNum, position=pos)
	columnNum += 1

	if hasSpecialAA():
		if hasattr(node, 'specialAA'):
			aa_face = TextFace(node.specialAA)
			aa_face.background.color = aminoAcidTreeColorMap[node.specialAA].color
		else:
			aa_face = TextFace(" ")
			aa_face.background.color = "Black"

		node.add_face(aa_face, column=columnNum, position=pos)
		columnNum += 1

	if hasTaxa():
		if hasattr(node, 'taxonOfInterest'):
			it_face = TextFace(" " + node.taxonOfInterest)
			it_face.fgcolor = taxonColorMap[node.taxonOfInterest].color
		else:
			it_face = TextFace(" ")
			it_face.fgcolor = "Black"

		it_face.margin_top = 4
		it_face.margin_bottom = 4
		node.add_face(it_face, column=columnNum, position=pos)
		columnNum += 1

	if not node.img_style["draw_descendants"]:
		node.add_face(TextFace(" " + node.cladeName), column=columnNum, position=pos)
		columnNum += 1

###############################################################################
def collapsedSimpleNodeLayout(node, columnNum, marginLeft, doCountLeaves, pos):

	simple_motifs = [
		# seq.start, seq.end, shape, width, height, fgcolor, bgcolor
		[0, 5, "<", None, 30, node.img_style["fgcolor"], node.img_style["fgcolor"], ""],
	]

	seq_face = SeqMotifFace(motifs=simple_motifs)
	seq_face.margin_left = marginLeft
	seq_face.rotable = False
	node.add_face(seq_face, column=columnNum, position="branch-right")
	columnNum += 1

	numLeavesStr = (" - " + str(countLeaves(node)) + " ") if doCountLeaves else ""
	name_face = TextFace(" " + node.cladeName + numLeavesStr)
	# Add the name face to the image at the preferred position
	node.add_face(name_face, column=columnNum, position=pos)
	columnNum += 1

	return columnNum

###############################################################################
def collapsedNodeLayout(node, columnNum, marginLeft, pos):
	columnNum = collapsedSimpleNodeLayout(node, columnNum, marginLeft, True, pos)

	if hasSpecialAA():
		percents, colors = getColorsAndPercents(node, aminoAcidTreeColorMap, 'specialAA')
		pie_face = PieChartFace(percents, 30, 30, colors)
		pie_face.margin_top = 4
		pie_face.margin_bottom = 4
		node.add_face(pie_face, column=columnNum, position=pos)
		columnNum += 1

	if hasTaxa():
		node.add_face(TextFace(" ", fsize=10), column=columnNum, position=pos)
		columnNum += 1
		percents, colors = getColorsAndPercents(node, taxonColorMap, 'taxonOfInterest')
		pie_face = PieChartFace(percents, 30, 30, colors)
		pie_face.margin_top = 4
		pie_face.margin_bottom = 4
		node.add_face(pie_face, column=columnNum, position=pos)
		columnNum += 1

###############################################################################
def addSupportValues(node):
		# If internal node, draws label with smaller font size
		if node.name == "":
			name_face = TextFace(" ", fsize=10)
		else:
			color = getSupportOverThresholdColor(node.name)
			name_face = AttrFace("name", fsize=10, fgcolor=color)
		# Add the name face to the image at the preferred position
		node.add_face(name_face, column=0, position="branch-top")

###############################################################################
def colorNodes(node, cladeColor, cladeBackgroundTextColor):
	nodeStyle = NodeStyle()
	nodeStyle["vt_line_color"] = cladeColor
	nodeStyle["hz_line_color"] = cladeColor
	nodeStyle["vt_line_width"] = lineWidth
	nodeStyle["hz_line_width"] = lineWidth
	nodeStyle["fgcolor"] = cladeColor
	nodeStyle["size"] = nodeShapeSize
	nodeStyle["shape"] = "square"
	nodeStyle.faces_bgcolor = cladeBackgroundTextColor

	# Add the style to this node
	node.set_style(nodeStyle)

	# Add the style to all descendants
	for descendant in node.iter_descendants():
		descendant.img_style = nodeStyle

###############################################################################
def colorCollapsedNode(node, cladeColor, cladeBackgroundTextColor):
	nodeStyle = NodeStyle()
	nodeStyle["vt_line_color"] = cladeColor
	nodeStyle["hz_line_color"] = cladeColor
	nodeStyle["vt_line_width"] = lineWidth
	nodeStyle["hz_line_width"] = lineWidth
	nodeStyle["fgcolor"] = cladeColor
	nodeStyle["size"] = nodeShapeSize #* 2
	nodeStyle["shape"] = "square"
	nodeStyle.faces_bgcolor = cladeBackgroundTextColor

	# Add the style to this node
	node.set_style(nodeStyle)

###############################################################################
def initClades(tree):
	for node in tree.traverse():
		node.clades = 0
		node.cladeName = ""

###############################################################################
def loadCladeInfo(tree, fileName, cladeTreeFile):
	clades = []

	with open(fileName, newline='') as cladeFile:
		cladeReader = csv.reader(cladeFile, delimiter='\t')
		for row in cladeReader:
			# Continue if the line is empty
			if not row:
				continue

			# Better check for the comment character
			if len(row) < 4:
				continue

			# Continue if the label is not among the nodes
			leafNode = getLeaveOfClade(tree, row[0], row[1], cladeTreeFile)
			if not leafNode:
				continue

			clade = Clade(row[0], row[1], row[2], row[3], leafNode)
			clades.append(clade)
	return clades

###############################################################################
def cladifyNodes(tree, clades):
	initClades(tree)
	for clade in clades:
		# Browse the tree from the clade defining leaf to root
		node = clade.typeNode
		while node:
			node.clades += 1
			node = node.up

###############################################################################
def getLeaveOfClade(tree, cladeSeqId, cladeName, cladeTreeFile):
	if cladeTreeFile == '':
		node = tree.search_nodes(name=cladeSeqId)
		if len(node) > 0:
			return node[0]
		else:
			return None
	else:
		node = tree.search_nodes(name=cladeSeqId)
		if len(node) > 0:
			return node[0]

		with open(cladeTreeFile, "r") as cladeTrees:
			for line in cladeTrees:
				subtree = Tree(line, format=3)
				if subtree.name == cladeName:
					collectedNodes = []
					for leaf in subtree.iter_leaves():
						nodeList = tree.get_leaves_by_name(leaf.name)
						if len(nodeList) > 0:
							collectedNodes.append(nodeList[0])

					if len(collectedNodes) <= 0:
						continue

					middleNode = int((len(collectedNodes) - 1) / 2)

					return collectedNodes[middleNode]

		return None

###############################################################################
def initialReroot(tree, clades):
	clade = clades[-1] # Use the last clade for rooting
	tree.set_outgroup(clade.typeNode)

###############################################################################
def rerootToOutgroup(tree, clades):

	cladesNum = tree.clades - 1
	for clade in clades:
		# Browse the tree from the clade defining leaf to the root
		node = clade.typeNode

		if clade.name == clades[-1].name:
			continue

		while node:
			if node.up and node.up.clades < cladesNum:
				node = node.up
			else:
				if node.up:
					node = node.up

				tree.set_outgroup(node)
				break
		break

###############################################################################
def getCladeRootNode(node):
	# Browse the tree from the clade defining leaf to the root
	while node:
		if node.up and node.up.clades == 1:
			node = node.up
		else:
			return node
	
###############################################################################
def assignCladeNameToCenterLeaf(node, cladeName):
	counter = 0
	for leaf in node.iter_leaves():
		counter += 1

	halfCounter = int(counter / 2)

	counter = 0
	for leaf in node.iter_leaves():
		if halfCounter == counter:
			leaf.cladeName = cladeName
			break

		counter += 1

###############################################################################
def colorAndNameClades(tree, clades):
	colorNodes(tree, "Black", "White")
	for clade in clades:

		assignCladeNameToCenterLeaf(clade.rootNode, clade.name)
		colorNodes(clade.rootNode, clade.forgroundColor, clade.backgroundColor)

###############################################################################
def saveCladesAsTrees(tree, clades, outputFile):
	with open(outputFile, "w") as outFile:
		for clade in clades:
			node = tree.search_nodes(name=clade.typeSeqID)[0]

			tmpName = clade.rootNode.name
			clade.rootNode.name = clade.name
			outFile.write(clade.rootNode.write(format=3) + "\n")
#			outFile.write("(" + clade.rootNode.write()[:-1] + ")" + clade.name + ";\n")
			clade.rootNode.name = tmpName

###############################################################################
def nameCladeRoots(tree, clades):
	for clade in clades:

		clade.rootNode = getCladeRootNode(clade.typeNode)
		if clade.rootNode.name == "":
			for child in clade.rootNode.children:
				if child.is_leaf():
					continue

				if child.name != "":
					clade.rootNode.name = child.name + "/*"
					break

###############################################################################
def collapseTree(tree, clades):
	for clade in clades:

		clade.rootNode.cladeName = clade.name
		colorCollapsedNode(clade.rootNode, clade.forgroundColor, clade.backgroundColor)

		clade.rootNode.img_style["draw_descendants"] = False

###############################################################################
def getFullTreeStyle():
	ts = TreeStyle()
	#ts = "c" # draw tree in circular mode
	#ts.scale = 20

	# Do not add leaf names automatically
	ts.show_leaf_name = False
	# Use my custom layout
	ts.layout_fn = fullTreeLayout
	# Do not show the scale bar
	ts.show_scale = False
	# Use dotted guide lines between leaves and labels
	ts.draw_guiding_lines = True

	return ts

###############################################################################
def getCollapsedSimpleTreeStyle():
	ts = TreeStyle()
	# Do not add leaf names automatically
	ts.show_leaf_name = False
	# Use my custom layout
	ts.layout_fn = collapsedSimpleTreeLayout
	# Do not show the scale bar
	ts.show_scale = False

	return ts

###############################################################################
def getCollapsedTreeStyle():
	ts = TreeStyle()
	# Do not add leaf names automatically
	ts.show_leaf_name = False
	# Use my custom layout
	ts.layout_fn = collapsedTreeLayout
	# Do not show the scale bar
	ts.show_scale = False

	return ts

###############################################################################
def getLegendOnlyStyle(tree):
	ts = TreeStyle()
	# Do not add leaf names automatically
	ts.show_leaf_name = False
	# Use my custom layout
	ts.layout_fn = noTreeLayout
	# Do not show the scale bar
	ts.show_scale = False

	ts.legend_position = 4

	countMap , numLeaves  = countAttributes(tree,             'taxonOfInterest')
	countMapR, numLeavesR = countAttributes(tree.children[0], 'taxonOfInterest')
	countMapL, numLeavesL = countAttributes(tree.children[1], 'taxonOfInterest')

	title    = ""
	total    = ""
	ingroup  = ""
	outgroup = ""
	unknown  = ""
	for taxon in taxonColorMap:
		data = taxonColorMap[taxon]
		if data.entryType == type_title:
			title    = taxon
		if data.entryType == type_total:
			total  = taxon
		if data.entryType == type_ingroup:
			ingroup  = taxon
		if data.entryType == type_outgroup:
			outgroup = taxon
		if data.entryType == type_unknown:
			unknown  = taxon

	ts.legend.add_face(TextFace(title),    column=0)
	ts.legend.add_face(TextFace(' '),      column=1)
	ts.legend.add_face(TextFace(total),    column=2)
	ts.legend.add_face(TextFace(' '),      column=3)
	ts.legend.add_face(TextFace(ingroup),  column=4)
	ts.legend.add_face(TextFace(' '),      column=5)
	ts.legend.add_face(TextFace(outgroup), column=6)

	ts.legend.add_face(TextFace(' '),      column=0)
	ts.legend.add_face(TextFace(' '),      column=1)
	ts.legend.add_face(TextFace(' '),      column=2)
	ts.legend.add_face(TextFace(' '),      column=3)
	ts.legend.add_face(TextFace(' '),      column=4)
	ts.legend.add_face(TextFace(' '),      column=5)
	ts.legend.add_face(TextFace(' '),      column=6)

	allNum = 0
	inNum  = 0
	outNum = 0

	for taxon in taxonColorMap:
		data = taxonColorMap[taxon]
		
		if data.entryType != type_regular and data.entryType != type_legend:
			continue

		rank = data.rank * 2 * '.'

		if data.entryType == type_regular:
			if taxon in countMap:
				taxonNum = str(countMap[taxon]) + ' '
				allNum += countMap[taxon]
			else:
				taxonNum = str(0) + ' '
		else:
			taxonNum = ' '

		if taxon == "_" and unknown != "":
			showTaxon = unknown
		else:
			showTaxon = taxon


		textFace = TextFace(rank + showTaxon)
		textFace.fgcolor = data.color
		ts.legend.add_face(textFace, column=0)

		ts.legend.add_face(TextFace(' '), column=1)

		textFace = TextFace(taxonNum)
		textFace.fgcolor = data.color
		textFace.hz_align = 2
		ts.legend.add_face(textFace, column=2)

		ts.legend.add_face(TextFace(' '), column=3)

		if data.entryType == type_regular:
			if taxon in countMapR:
				taxonNum = str(countMapR[taxon]) + ' '
				inNum += countMapR[taxon]
			else:
				taxonNum = str(0) + ' '
		else:
			taxonNum = ' '

		textFace = TextFace(taxonNum)
		textFace.fgcolor = data.color
		textFace.hz_align = 2
		ts.legend.add_face(textFace, column=4)

		ts.legend.add_face(TextFace(' '), column=5)

		if data.entryType == type_regular:
			if taxon in countMapL:
				taxonNum = str(countMapL[taxon]) + ' '
				outNum += countMapL[taxon]
			else:
				taxonNum = str(0) + ' '
		else:
			taxonNum = ' '

		textFace = TextFace(taxonNum)
		textFace.fgcolor = data.color
		textFace.hz_align = 2
		ts.legend.add_face(textFace, column=6)

	ts.legend.add_face(TextFace(' '),      column=0)
	ts.legend.add_face(TextFace(' '),      column=1)
	ts.legend.add_face(TextFace(' '),      column=2)
	ts.legend.add_face(TextFace(' '),      column=3)
	ts.legend.add_face(TextFace(' '),      column=4)
	ts.legend.add_face(TextFace(' '),      column=5)
	ts.legend.add_face(TextFace(' '),      column=6)

	textAll      = TextFace(str(allNum)  + ' ')
	textIngroup  = TextFace(str(inNum)   + ' ')
	textOutgroup = TextFace(str(outNum)  + ' ')

	textAll      .hz_align = 2
	textIngroup  .hz_align = 2
	textOutgroup .hz_align = 2

	ts.legend.add_face(TextFace(total), column=0)
	ts.legend.add_face(TextFace(' '),   column=1)
	ts.legend.add_face(textAll,         column=2)
	ts.legend.add_face(TextFace(' '),   column=3)
	ts.legend.add_face(textIngroup,     column=4)
	ts.legend.add_face(TextFace(' '),   column=5)
	ts.legend.add_face(textOutgroup,    column=6)

	return ts

###############################################################################
def usage(progName):
	print(progName, "annotates a tree from a newick file with clades and draws a full")
	print("version of the tree and a version with clades collapsed.\n")
	print(' -h, --help                                Prints this help message.')
	print(' -i, --infile              <infile>        The input file with the newick tree to visualize.')
	print(' -t, --trees               <cladetreefile> The tree file with the subclade trees to visualize input trees with sub data set.')
	print(' -c, --cladefile           <cladefile>     The clade file, a tab separated list with a clade per line.')
	print('                                           Each clade is defined by a leaf name, the clade name,')
	print('                                           a foreground color, and a color for a background with black font on.')
	print(' -f, --refSeqConfigFile    <configFile>    A config file with a reference sequence file path and positions of interesting')
	print('                                           amino acid positions in the reference sequence file. Such as the')
	print('                                           lysine at position 296 in cattle rhodopsin. This position is then displayed')
	print('                                           on the trees and used for the sequence logo.')
	print('                                           This option is ignored if configFile does not exist.')
	print('')

###############################################################################

def parseArgs(progName, argv):
	# ToDo turn these bunch of values into an opject
	infile              = ""
	cladeFile           = ""
	cladeTreeFile       = ""
	refSeqFile          = ""
	specialAminoAcidPos = -1
	iterestingTaxa      = ""
	customAA            = ""
	additionalTaxa      = ""
	makeLogos           = False
	refSeqConfigData    = None

	try:
		opts, args = getopt.getopt(argv,"hmt:i:c:f:z:a:x:",["help", "makeLogos", "infile=", "cladefile=", "trees=", "refSeqConfigFile=", "iterestingTaxa", "customAA", "additionalTaxa"])
	except getopt.GetoptError as err:
		print(err, "\n")
		usage(progName)
		sys.exit(2)
	for opt, arg in opts:
		if opt in ("-h", "--help"):
			usage(progName)
			sys.exit()
		elif opt in ("-m", "--makeLogos"):
			makeLogos = True
		elif opt in ("-i", "--infile"):
			infile = arg
		elif opt in ("-c", "--cladefile"):
			cladeFile = arg
		elif opt in ("-t", "--trees"):
			cladeTreeFile = arg
		elif opt in ("-f", "--refSeqConfigFile"):
			if os.path.isfile(arg):
				refSeqConfigData = ConfigData(arg)
		elif opt in ("-z", "--iterestingTaxa"):
			iterestingTaxa = arg
		elif opt in ("-a", "--customAA"):
			customAA = arg
		elif opt in ("-x", "--additionalTaxa"):
			additionalTaxa = arg

	return infile, cladeFile, cladeTreeFile, refSeqConfigData, iterestingTaxa, customAA, additionalTaxa, makeLogos

###############################################################################
def loadTaxa(iterestingTaxa, additionalTaxa):
	if iterestingTaxa == "":
		return

	loadColorMap(iterestingTaxa, taxonColorMap)

	genusDatabase = "SpeciesDatabase/GenusLinage.csv"
	f = open(genusDatabase, 'rt')

	while True:
		line = f.readline()
		if not line:
			break

		splitLine = line.split("\t")

		for taxon in taxonColorMap:
			if taxonColorMap[taxon].entryType == type_regular:
				checkString = " " + taxon + ";"
				if checkString in splitLine[2]:
					genusInterestingTaxaMap[splitLine[1]] = taxon

	if additionalTaxa == "":
		return

	f = open(additionalTaxa, 'rt')

	while True:
		line = f.readline()
		if not line:
			break
		if line[0] == '#':
			continue

		splitLine = line.split("\t")

		for taxon in taxonColorMap:
			if taxonColorMap[taxon].entryType == type_regular:
				if taxon in splitLine[1]:
					genusInterestingTaxaMap[splitLine[0]] = taxon

###############################################################################
def addHigherTaxaOfInterest(tree):
	if not hasTaxa():
		return

	for leaf in tree.iter_leaves():
		nameSplit = leaf.name.split("_")
		for string in nameSplit:
			if string in genusInterestingTaxaMap:
				leaf.taxonOfInterest = genusInterestingTaxaMap[string]
				# Break here, not only to reduce the run-time, but species names
				# can also occur as genus names
				break

###############################################################################

if __name__ == "__main__":
	# Execute only if run as main script

	inputTree, inputClades, cladeTreeFile, refSeqConfigData, iterestingTaxa, customAA, additionalTaxa, makeLogos = parseArgs(sys.argv[0], sys.argv[1:])

	alignmentData = AlignmentData(cladeTreeFile)
	if refSeqConfigData:
		refSeqConfigData.setAlignmentData(alignmentData)

	cladeBase = os.path.basename(inputClades)
	cladeBase = os.path.splitext(cladeBase)[0]

	cladeTrees             = inputTree + "." + cladeBase + ".cladeTrees"
	outCollapsedTree       = inputTree + "." + cladeBase + ".collapsedTree"
	outFullTree            = inputTree + "." + cladeBase + ".fullTree"
	logoOutFileBase        = inputTree + "." + cladeBase
	sortedAlignmentFile    = inputTree + "." + cladeBase + ".treeSorted.fasta"
#	outFullTreeNeXML       = inputTree + "." + cladeBase + ".fullTree.NeXML"

	print("Load tree:", inputTree, file=sys.stderr)

	formats = [3, 1]
	for f in formats:
		try:
			tree = Tree(inputTree, format=f)
			break
		except:
			continue

	logging.debug("Remove single quotation marks: " + inputTree)
	for node in tree.traverse():
		node.name = node.name.replace('\'', '')

	if refSeqConfigData != None:
		logging.debug("Load amino acid information: " + inputTree)
		colorMapFileName = "AminoAcidColorMap.csv"
		loadColorMap(colorMapFileName, aminoAcidColorMap)
		determineSpecialAminoAcidsAtPos(tree, refSeqConfigData)
		if customAA != "":
			print(customAA)
			loadColorMap(customAA, aminoAcidTreeColorMap)
		else:
			aminoAcidTreeColorMap = aminoAcidColorMap

	logging.debug("Load taxon information: " + inputTree)
	loadTaxa(iterestingTaxa, additionalTaxa)

	logging.debug("Load clade information: " + inputTree)
	clades = loadCladeInfo(tree, inputClades, cladeTreeFile)
	logging.debug("Initial reroot for tree: " + inputTree)
	initialReroot(tree, clades)
	logging.debug("Determine clades for tree: " + inputTree)
	cladifyNodes(tree, clades)
	logging.debug("Find higher taxa for sequences: " + inputTree)
	addHigherTaxaOfInterest(tree)

	# Root the tree at the outgroup
	logging.debug("Final reroot " + inputTree)
	rerootToOutgroup(tree, clades)

	# Reinitialize the clades, since they were changed by rerooting
	logging.debug("Determine clades for tree after reroot: " + inputTree)
	cladifyNodes(tree, clades)
	logging.debug("Get clade roots: " + inputTree)
	nameCladeRoots(tree, clades)

	logging.debug("Color the clades: " + inputTree)
	colorAndNameClades(tree, clades)

	if makeLogos and refSeqConfigData != None:
		logging.debug("Make sequence logos: " + logoOutFileBase)
		makeSeqLogo(tree, clades, refSeqConfigData, logoOutFileBase)

	isFullTree = (cladeTreeFile == "")
	if isFullTree:
		logging.debug("Sort master alignment: " + cladeTrees)
		sortMasterAlignment(tree, alignmentData, sortedAlignmentFile)
		logging.debug("Save the clades:" + cladeTrees)
		saveCladesAsTrees(tree, clades, cladeTrees)

	# We must copy the tree here, since the render function adds faces we cannot remove
	# and would still show up at the second rendering
	logging.debug("Save full tree: " + outFullTree)
	fullTree = tree.copy()
	ts = getFullTreeStyle()

	fullTree.render(outFullTree + ".pdf", dpi=600, w=183, units="mm", tree_style=ts)
	# svg files are not printed corrected, they have duplicated text
#	fullTree.render(outFullTree + ".svg", dpi=600, w=183, units="mm", tree_style=ts)

	# Dendroscope cannot load this type of tree
	#nexml_project = nexml.Nexml()
	#tree_collection = nexml.Trees()
	#tree_collection.add_tree(tree)
	#nexml_project.add_trees(tree_collection)

	#with open(outFullTreeNeXML, "w") as outFile:
	#	nexml_project.export(outFile)
	# Even with removing this extra junk Dendroscope cannot load the tree
	# This may still be code to fix
	#command = "sed -i -e \"s/b'//g\"  -e \"s/\\\"'/\\\"/g\" " + outFullTreeNeXML
	#os.system(command)

	logging.debug("Save collapsed tree: " + outCollapsedTree)
	collapseTree(tree, clades)

	collTree = tree.copy()

	ts = getCollapsedTreeStyle()
	collTree.render(outCollapsedTree + ".pdf", dpi=600, w=400, units="mm", tree_style=ts)

	comTree = tree.copy()

	ts.layout_fn = collapsedCompactTreeLayout

	comTree.render(outCollapsedTree + "Com.pdf", dpi=600, w=400, units="mm", tree_style=ts)
#	comTree.render(outCollapsedTree + "Com.svg", dpi=600, w=400, units="mm", tree_style=ts)

	simpleTree = tree.copy()
	ts = getCollapsedSimpleTreeStyle()
	simpleTree.render(outCollapsedTree + "Simple.pdf", dpi=600, w=400, units="mm", tree_style=ts)

	noSupportTree = tree.copy()
	ts.layout_fn = collapsedSimpleNoSupportTreeLayout
	noSupportTree.render(outCollapsedTree + "SimpleNoSupp.pdf", dpi=600, w=400, units="mm", tree_style=ts)

	# Draw only the legend
	ts = getLegendOnlyStyle(tree)
	tree.img_style["vt_line_color"] = "White"
	tree.img_style["hz_line_color"] = "White"
	tree.img_style["vt_line_width"] = 0
	tree.img_style["hz_line_width"] = 0
	tree.img_style["fgcolor"] = "White"
	tree.img_style["size"] =  0
	tree.faces_bgcolor = "White"
	tree.img_style["draw_descendants"] = False
	tree.render(outCollapsedTree + "Legend.pdf", dpi=600, w=400, units="mm", tree_style=ts)

###############################################################################
