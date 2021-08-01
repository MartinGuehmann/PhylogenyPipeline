#!/bin/python3

from ete3 import Tree, NexmlTree, nexml, faces, AttrFace, TextFace, SeqMotifFace, PieChartFace, TreeStyle, NodeStyle
import csv
from inspect import getmembers
from Bio import AlignIO, Align

import os # Strip extension from file
import sys, getopt # Parse program arguments

# Sequence logo
import numpy as np
import pandas as pd
import matplotlib.pyplot as plt
import logomaker as logomaker

lineWidth = 4
margin = 4 / 2
nodeShapeSize = lineWidth - 1

SHaLRTTreshold = 80
aBayesTreshold = 0.95
UFBootTreshold = 95

type_regular  = 0
type_legend   = 1
type_title    = 2
type_total    = 3
type_ingroup  = 4
type_outgroup = 5
type_unknown  = 6

# Global maps
aminoAcidColorMap       = {}
taxonColorMap           = {}
genusInterestingTaxaMap = {}

###############################################################################
class ColorData:
	def __init__(self, color, entryType, rank):
		self.color     = color
		self.entryType = entryType
		self.rank      = rank

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
def hasSpecialAA():
	return len(aminoAcidColorMap) > 0

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
def makeSeqLogo(clades, masterAlignmentFileName, specialAAIndex, refSeqFile, logoOutFile):

	masterAlignment = AlignIO.read(masterAlignmentFileName, "phylip-relaxed")
	specialAAinAlignmentIndex = getSpecialAAInAlignment(masterAlignment, specialAAIndex, refSeqFile)

	if specialAAinAlignmentIndex < 0:
		return

	# ToDo load this externally
	lowerLimit = specialAAinAlignmentIndex - 9
	if lowerLimit < 0:
		lowerLimit = 0

	# ToDo load this externally
	upperLimit = specialAAinAlignmentIndex + 29
	if upperLimit >= masterAlignment.get_alignment_length():
		upperLimit = masterAlignment.get_alignment_length() -1

	collspan = upperLimit - lowerLimit

	numClades = len(clades)
	numItems = 1

	# Make figure
	rowHeight = 0.8
	colWidth  = 1.5 * collspan
	logoFigure = plt.figure(figsize=[colWidth * numItems, rowHeight * numClades])

	sequenceMap = {}
	for record in masterAlignment:
		sequenceMap[record.id] = record

	i = 0
	for clade in clades:

		sequences = []
		for leaf in clade.rootNode.iter_leaves():
			if leaf.name in sequenceMap:
				record = sequenceMap[leaf.name]
				sequences.append(str(record.seq[lowerLimit:upperLimit]))

		print("Make " + str(i+1) + ". of " + str(numClades) + " SeqLogos for the clade " + clade.name, file=sys.stderr)
		ax = plt.subplot2grid((numClades, 1), (i, 0))#, collspan=collspan
		ax.set_title(str(i+1) + " " + clade.name)
		dataMatrix = logomaker.alignment_to_matrix(sequences)
		seqLogo = logomaker.Logo(dataMatrix, ax=ax)
		i += 1

	logoFigure.savefig(logoOutFile, format='pdf')
#	sys.exit(2)

###############################################################################
def determineSpecialAminoAcidsAtPos(tree, masterAlignmentFileName, specialAAIndex, refSeqFile):

	masterAlignment = AlignIO.read(masterAlignmentFileName, "phylip-relaxed")
	specialAAinAlignmentIndex = getSpecialAAInAlignment(masterAlignment, specialAAIndex, refSeqFile)

	if specialAAinAlignmentIndex < 0:
		return

	sequenceMap = {}
	for record in masterAlignment:
		sequenceMap[record.id] = record

	for leaf in tree.iter_leaves():
		if leaf.name in sequenceMap:
			record = sequenceMap[leaf.name]
			leaf.specialAA = record[specialAAinAlignmentIndex].upper()

###############################################################################
def getSpecialAAInAlignment(masterAlignment, specialAAIndex, refSeqFile):
	refSequence = AlignIO.read(refSeqFile, "fasta")

	for record in masterAlignment:
		if refSequence[0].id in record.id:

			gapFreeRecord = record.seq.ungap()
			aligner = Align.PairwiseAligner()
			aligner.mode = 'global'
			alignments = aligner.align(refSequence[0].seq, gapFreeRecord)

			lastPos = 0
			thisPos = 0
			numGaps = 0
			for pair in alignments[0].aligned[0]:
				thisPos  = pair[0]
				numGaps += thisPos - lastPos
				lastPos  = pair[1]
				if lastPos > specialAAIndex:
					break

			i = 0
			aaIndex = numGaps + 1 # This is zero indexed but specialAAIndex is one indexed, so add one to account for that
			while i < len(record):
				if record[i] == "-":
					i += 1
					continue

				if aaIndex == specialAAIndex:
					return i

				aaIndex += 1
				i += 1

	return -1

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
			if(float(supportValues[0]) >= SHaLRTTreshold and
			   float(supportValues[1]) >= aBayesTreshold and
			     int(supportValues[2]) >= UFBootTreshold):
				return 'Black'
		except ValueError:
			pass
	else:
		try:
			if(  int(supportValues[0]) > UFBootTreshold):
				return 'Black'
		except ValueError:
			pass

	return 'Gray'

###############################################################################
def fullTreeLayout(node):
	if node.is_leaf():

		columnNum = 0
		if hasSpecialAA():
			if hasattr(node, 'specialAA'):
				aa_face = TextFace(node.specialAA)
				aa_face.background.color = aminoAcidColorMap[node.specialAA].color
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
		# If internal node, draws label with smaller font size
		if node.name == "":
			name_face = TextFace(" ", fsize=10)
		else:
			color = getSupportOverThresholdColor(node.name)
			name_face = AttrFace("name", fsize=10, fgcolor=color)

		# Add the name face to the image at the preferred position
		faces.add_face_to_node(name_face, node, column=0, position="branch-top")

###############################################################################
def collapsedTreeLayout(node):
	if node.is_leaf():
		columnNum = 0

		# If terminal node, draws it name
		if node.name == "":
			name_face =  TextFace(" ")
		else:
			name_face = AttrFace("name", text_prefix=" ", text_suffix=" ")

		name_face.margin_top = -2
		# Add the name face to the image at the preferred position
		node.add_face(name_face, column=columnNum, position="branch-right")
		columnNum += 1

		if hasSpecialAA():
			if hasattr(node, 'specialAA'):
				aa_face = TextFace(node.specialAA)
				aa_face.background.color = aminoAcidColorMap[node.specialAA].color
			else:
				aa_face = TextFace(" ")
				aa_face.background.color = "Black"

			node.add_face(aa_face, column=columnNum, position="branch-right")
			columnNum += 1

		if hasTaxa():
			if hasattr(node, 'taxonOfInterest'):
				it_face = TextFace(" " + node.taxonOfInterest)
				it_face.fgcolor = taxonColorMap[node.taxonOfInterest].color
			else:
				it_face = TextFace(" ")
				it_face.fgcolor = "Black"

			it_face.margin_top = 2
			it_face.margin_bottom = 2
			node.add_face(it_face, column=columnNum, position="branch-right")
			columnNum += 1

		if not node.img_style["draw_descendants"]:
			node.add_face(TextFace(" " + node.cladeName), column=columnNum, position="branch-right")
			columnNum += 1

	elif not node.img_style["draw_descendants"]:
		# Technically this is an internal node
		columnNum = 0

		simple_motifs = [
			# seq.start, seq.end, shape, width, height, fgcolor, bgcolor
			[0, 5, "<", None, 30, node.img_style["fgcolor"], node.img_style["fgcolor"], ""],
		]

		seq_face = SeqMotifFace(motifs=simple_motifs)
		seq_face.margin_left = -2
		seq_face.rotable = False
		node.add_face(seq_face, column=columnNum, position="branch-right")
		columnNum += 1

		# If internal node, draws label with smaller font size
		if node.name == "":
			name_face = TextFace(" ", fsize=10)
		else:
			color = getSupportOverThresholdColor(node.name)
			name_face = AttrFace("name", fsize=10, fgcolor=color)

		# Add the name face to the image at the preferred position
		node.add_face(name_face, column=0, position="branch-top") # Branch-top is 0

		# If terminal node, draws its name
		name_face = TextFace(" " + node.cladeName + " - " + str(countLeaves(node)) + " ")
		name_face.margin_top = -2
		# Add the name face to the image at the preferred position
		node.add_face(name_face, column=columnNum, position="branch-right")
		columnNum += 1

		if hasSpecialAA():
			percents, colors = getColorsAndPercents(node, aminoAcidColorMap, 'specialAA')
			pie_face = PieChartFace(percents, 30, 30, colors)
			node.add_face(pie_face, column=columnNum, position="branch-right")
			columnNum += 1

		if hasTaxa():
			node.add_face(TextFace(" ", fsize=10), column=columnNum, position="branch-right")
			columnNum += 1
			percents, colors = getColorsAndPercents(node, taxonColorMap, 'taxonOfInterest')
			pie_face = PieChartFace(percents, 30, 30, colors)
			node.add_face(pie_face, column=columnNum, position="branch-right")
			columnNum += 1

	else:
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
	# 120 pixels per branch length unit
	#ts.scale =  120
	# Use dotted guide lines between leaves and labels
	ts.draw_guiding_lines = True
	#ts.draw_aligned_faces_as_table = False
	#ts.allow_face_overlap = True
	return ts

###############################################################################
def getCollapsedTreeStyle(tree):
	ts = TreeStyle()
	# Do not add leaf names automatically
	ts.show_leaf_name = False
	# Use my custom layout
	ts.layout_fn = collapsedTreeLayout
	# 120 pixels per branch length unit
#	ts.scale =  120
	# Use dotted guide lines between leaves and labels
#	ts.draw_guiding_lines = True

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

	for taxon in taxonColorMap:
		data = taxonColorMap[taxon]
		
		if data.entryType != type_regular and data.entryType != type_legend:
			continue

		rank = data.rank * 2 * '.'

		if data.entryType == type_regular:
			if taxon in countMap:
				taxonNum = str(countMap[taxon]) + ' '
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
			else:
				taxonNum = str(0) + ' '
		else:
			taxonNum = ' '

		textFace = TextFace(taxonNum)
		textFace.fgcolor = data.color
		textFace.hz_align = 2
		ts.legend.add_face(textFace, column=6)

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
	print(' -f, --refSeqFile          <cladetreefile> A reference sequence file in fasta format, for mapping a position, such as the')
	print('                                           lysine at position 296 in cattle rhodopsin. This position is then displayed')
	print('                                           on the trees.')
	print(' -p, --specialAminoAcidPos <int>           The position of the amino acid of interest in the reference sequence.')
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
	makeLogos           = False

	try:
		opts, args = getopt.getopt(argv,"hmt:i:c:f:p:z:",["help", "makeLogos", "infile=", "cladefile=", "trees=", "refSeqFile=", "specialAminoAcidPos=", "iterestingTaxa"])
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
		elif opt in ("-f", "--refSeqFile"):
			refSeqFile = arg
		elif opt in ("-p", "--specialAminoAcidPos"):
			specialAminoAcidPos = int(arg)
		elif opt in ("-z", "--iterestingTaxa"):
			iterestingTaxa = arg

	return infile, cladeFile, cladeTreeFile, refSeqFile, specialAminoAcidPos, iterestingTaxa, makeLogos

###############################################################################
def loadTaxa(iterestingTaxa):
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
					genusInterestingTaxaMap[splitLine[1].lower()] = taxon

###############################################################################
def addHigherTaxaOfInterest(tree):
	if not hasTaxa():
		return

	for leaf in tree.iter_leaves():
		nameSplit = leaf.name.lower().split("_")
		for string in nameSplit:
			if string in genusInterestingTaxaMap:
				leaf.taxonOfInterest = genusInterestingTaxaMap[string]
				# Break here, not only to reduce the run-time, but species names
				# can also occur as genus names
				break

###############################################################################

if __name__ == "__main__":
	# Execute only if run as main script

	inputTree, inputClades, cladeTreeFile, refSeqFile, specialAminoAcidPos, iterestingTaxa, makeLogos = parseArgs(sys.argv[0], sys.argv[1:])

	isFullTree = (cladeTreeFile == "")

	if isFullTree:
		alnFile = os.path.splitext(inputTree)[0]
	else:
		alnFile = os.path.splitext(os.path.splitext(os.path.splitext(cladeTreeFile)[0])[0])[0]

	cladeBase = os.path.basename(inputClades)
	cladeBase = os.path.splitext(cladeBase)[0]

	cladeTrees             = inputTree + "." + cladeBase + ".cladeTrees"
	outCollapsedTree       = inputTree + "." + cladeBase + ".collapsedTree.pdf"
	outFullTree            = inputTree + "." + cladeBase + ".fullTree.pdf"
	logoOutFile            = inputTree + "." + cladeBase + ".logo.pdf"
#	outFullTreeNeXML       = inputTree + "." + cladeBase + ".fullTree.NeXML"

	print("Load tree:", inputTree, file=sys.stderr)

	formats = [3, 1]
	for f in formats:
		try:
			tree = Tree(inputTree, format=f)
			break
		except:
			continue

	print("Remove single quotation marks:", inputTree, file=sys.stderr)
	for node in tree.traverse():
		node.name = node.name.replace('\'', '')

	if refSeqFile != "" and specialAminoAcidPos >= 0:
		print("Load amino acid information:", inputTree, file=sys.stderr)
		colorMapFileName = "AminoAcidColorMap.csv"
		loadColorMap(colorMapFileName, aminoAcidColorMap)
		print("Determine amino acid at", str(specialAminoAcidPos), "in", alnFile, file=sys.stderr)
		determineSpecialAminoAcidsAtPos(tree, alnFile, specialAminoAcidPos, refSeqFile)

	print("Load taxon information:", inputTree, file=sys.stderr)
	loadTaxa(iterestingTaxa)

	print("Load clade information:", inputTree, file=sys.stderr)
	clades = loadCladeInfo(tree, inputClades, cladeTreeFile)
	print("Initial reroot for tree:", inputTree, file=sys.stderr)
	initialReroot(tree, clades)
	print("Determine clades for tree:", inputTree, file=sys.stderr)
	cladifyNodes(tree, clades)
	print("Find higher taxa for sequences:", inputTree, file=sys.stderr)
	addHigherTaxaOfInterest(tree)

	# Root the tree at the outgroup
	print("Final reroot", inputTree, file=sys.stderr)
	rerootToOutgroup(tree, clades)

	# Reinitialize the clades, since they were changed by rerooting
	print("Determine clades for tree after reroot:", inputTree, file=sys.stderr)
	cladifyNodes(tree, clades)
	print("Get clade roots:", inputTree, file=sys.stderr)
	nameCladeRoots(tree, clades)

	print("Color the clades:", inputTree, file=sys.stderr)
	colorAndNameClades(tree, clades)

	if makeLogos:
		print("Make sequence logos:", logoOutFile, file=sys.stderr)
		makeSeqLogo(clades, alnFile, specialAminoAcidPos, refSeqFile, logoOutFile)

	if isFullTree:
		print("Saves the clades:", cladeTrees, file=sys.stderr)
		saveCladesAsTrees(tree, clades, cladeTrees)

	# We must copy the tree here, since the render function adds faces we cannot remove
	# and would still show up at the second rendering
	print("Saves full tree:", outFullTree, file=sys.stderr)
	fullTree = tree.copy()
	ts = getFullTreeStyle()

	fullTree.render(outFullTree, dpi=600, w=183, units="mm", tree_style=ts)

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

	print("Saves collapsed tree:", outCollapsedTree, file=sys.stderr)
	collapseTree(tree, clades)

	ts = getCollapsedTreeStyle(tree)
	tree.render(outCollapsedTree, dpi=600, w=400, units="mm", tree_style=ts)

###############################################################################
