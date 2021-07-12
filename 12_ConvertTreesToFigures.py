#!/bin/python3

from ete3 import Tree, NexmlTree, nexml, faces, AttrFace, TextFace, SeqMotifFace, PieChartFace, TreeStyle, NodeStyle
import csv
from inspect import getmembers
from Bio import AlignIO, Align

import os # Strip extension from file
import sys, getopt # Parse program arguments

lineWidth = 4
margin = 4 / 2
nodeShapeSize = lineWidth - 1

SHaLRTTreshold = 80
aBayesTreshold = 0.95
UFBootTreshold = 95

hasSpecialAA = False

# Global maps
aminoAcidColorMap = {}

###############################################################################
def getColorsAndPercents(tree):

	countMap = {}
	numLeaves = 0
	for leaf in tree.iter_leaves():
		if hasattr(leaf, 'specialAA'):
			if leaf.specialAA in countMap:
				countMap[leaf.specialAA] += 1
			else:
				countMap[leaf.specialAA] = 1
		else:
			if "_" in countMap:
				countMap["_"] += 1
			else:
				countMap["_"] = 1

		numLeaves += 1

	percents = []
	colors   = []
	for key, value in countMap.items():
		percents.append((value / numLeaves) * 100)
		if key in aminoAcidColorMap:
			colors.append(aminoAcidColorMap[key])
		else:
			colors.append("Black")

	return percents, colors

###############################################################################
def determineSpecialAminoAcidsAtPos(tree, masterAlignmentFileName, specialAAIndex, refSeqFile):
	masterAlignment = AlignIO.read(masterAlignmentFileName, "phylip-relaxed")
	specialAAinAlignmentIndex = getSpecialAAInAlignment(masterAlignment, specialAAIndex, refSeqFile)

	if specialAAinAlignmentIndex < 0:
		return

	for record in masterAlignment:

		specialAA = record[specialAAinAlignmentIndex]

		nodes = tree.search_nodes(name=record.id)
		if len(nodes) > 0:
			nodes[0].specialAA = record[specialAAinAlignmentIndex].upper()

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
def loadAminoAcidColors(colorMapFileName):
	with open(colorMapFileName, newline='') as colorMapFile:
		colorReader = csv.reader(colorMapFile, delimiter='\t')
		for row in colorReader:
			# Continue if the line is empty
			if not row:
				continue

			aminoAcidColorMap[row[0]] = row[1]


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

		if hasSpecialAA:
			if hasattr(node, 'specialAA'):
				aa_face = TextFace(node.specialAA)
				aa_face.background.color = aminoAcidColorMap[node.specialAA]
			else:
				aa_face = TextFace(" ")
				aa_face.background.color = "Black"

			aa_face.margin_top = 2
			aa_face.margin_bottom = 2
			node.add_face(aa_face, column=0, position="aligned")

		# If terminal node, draw its name
		if node.name == "":
			name_face = TextFace(" ")
		else:
			name_face = AttrFace("name")

		if hasattr(node.img_style, 'faces_bgcolor'):
			name_face.background.color = node.img_style.faces_bgcolor
			name_face.margin_top = 2
			name_face.margin_bottom = 2
		# Add the name face to the image at the preferred position
		node.add_face(name_face, column=1, position="aligned")

		rect_face = TextFace("                                            ")
		rect_face.background.color = node.img_style["fgcolor"]
		rect_face.margin_top = 2
		rect_face.margin_bottom = 2
		node.add_face(rect_face, column=2, position="aligned")
		if node.cladeName != "":
			clade_face = TextFace(node.cladeName, fsize=100)
			node.add_face(clade_face, column=3, position="float-right")

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
		# If terminal node, draws it name
		if node.name == "":
			name_face =  TextFace(" ")
		else:
			name_face = AttrFace("name", text_prefix=" ", text_suffix=" ")

		name_face.margin_top = -2
		# Add the name face to the image at the preferred position
		node.add_face(name_face, column=0, position="branch-right")

		if hasSpecialAA:
			if hasattr(node, 'specialAA'):
				aa_face = TextFace(node.specialAA)
				aa_face.background.color = aminoAcidColorMap[node.specialAA]
			else:
				aa_face = TextFace(" ")
				aa_face.background.color = "Black"

			node.add_face(aa_face, column=1, position="branch-right")

		if not node.img_style["draw_descendants"]:
			node.add_face(TextFace(" "), column=2, position="branch-right")
			node.add_face(TextFace(node.cladeName), column=3, position="branch-right")

	elif not node.img_style["draw_descendants"]:
		# Technically this is an internal node

		simple_motifs = [
			# seq.start, seq.end, shape, width, height, fgcolor, bgcolor
			[0, 5, "<", None, 30, node.img_style["fgcolor"], node.img_style["fgcolor"], ""],
		]

		seq_face = SeqMotifFace(motifs=simple_motifs)
		seq_face.margin_left = -2
		node.add_face(seq_face, column=0, position="branch-right")

		# If internal node, draws label with smaller font size
		if node.name == "":
			name_face = TextFace(" ", fsize=10)
		else:
			color = getSupportOverThresholdColor(node.name)
			name_face = AttrFace("name", fsize=10, fgcolor=color)

		# Add the name face to the image at the preferred position
		node.add_face(name_face, column=0, position="branch-top")
		# If terminal node, draws its name

		name_face = TextFace(" " + node.cladeName + " - " + str(countLeaves(node)) + " ")
		name_face.margin_top = -2
		# Add the name face to the image at the preferred position
		node.add_face(name_face, column=1, position="branch-right")

		if hasSpecialAA:
			percents, colors = getColorsAndPercents(node)
			pie_face = PieChartFace(percents, 30, 30, colors) # , line_color="black"
			node.add_face(pie_face, column=2, position="branch-right")

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
			leafNode = getLeaveOfClade(tree, row, cladeTreeFile)
			if not leafNode:
				continue

			row.append(leafNode)  # This makes it the last element in row. It can be accessed by row[-1]
			clades.append(row)
	return clades

###############################################################################
def cladifyNodes(tree, clades):
	initClades(tree)
	for clade in clades:
		# Browse the tree from the clade defining leaf to root
		node = clade[-1]
		while node:
			node.clades += 1
			node = node.up

###############################################################################
def getLeaveOfClade(tree, clade, cladeTreeFile):
	if cladeTreeFile == '':
		node = tree.search_nodes(name=clade[0])
		if len(node) > 0:
			return node[0]
		else:
			return None
	else:
		node = tree.search_nodes(name=clade[0])
		if len(node) > 0:
			return node[0]

		with open(cladeTreeFile, "r") as cladeTrees:
			cladeName = clade[1]
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
	for clade in clades:
		node = clade[-1] # Get the last element
		cladeName = clade[1]
		if cladeName == "Outgroup":
			tree.set_outgroup(node)


###############################################################################
def rerootToOutgroup(tree, clades):

	cladesNum = tree.clades - 1
	for clade in clades:
		# Browse the tree from the clade defining leaf to the root
		node = clade[-1] # Get the last element
		cladeName = clade[1]

		if cladeName == "Outgroup":
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
		# Browse the tree from the clade defining leaf to the root
		node = clade[-1] # Get the last element
		cladeName = clade[1]
		cladeColor = clade[2]
		cladeBackgroundTextColor = clade[3]

		cladeRoot = getCladeRootNode(node)
		assignCladeNameToCenterLeaf(cladeRoot, cladeName)
		colorNodes(cladeRoot, cladeColor, cladeBackgroundTextColor)

###############################################################################
def saveCladesAsTrees(tree, clades, outputFile):
	with open(outputFile, "w") as outFile:
		for clade in clades:
			# Browse the tree from the clade defining leaf to the root
			node = tree.search_nodes(name=clade[0])[0]
			cladeName = clade[1]

			cladeRoot = getCladeRootNode(node)
			tmpName = cladeRoot.name
			cladeRoot.name = cladeName
			outFile.write(cladeRoot.write(format=3) + "\n")
#			outFile.write("(" + cladeRoot.write()[:-1] + ")" + cladeName + ";\n")
			cladeRoot.name = tmpName

###############################################################################
def nameCladeRoots(tree, clades):
	for clade in clades:
		# Browse the tree from the clade defining leaf to the root
		node = clade[-1] # Get the last element
		cladeName = clade[1]

		cladeRoot = getCladeRootNode(node)
		if cladeRoot.name == "":
			for child in cladeRoot.children:
				if child.is_leaf():
					continue

				if child.name != "":
					cladeRoot.name = child.name + "/*"
					break

###############################################################################
def collapseTree(tree, clades):
	for clade in clades:
		# Browse the tree from the clade defining leaf to the root
		node = clade[-1] # Get the last element
		cladeName = clade[1]
		cladeColor = clade[2]
		cladeBackgroundTextColor = clade[3]

		cladeRoot = getCladeRootNode(node)
		cladeRoot.cladeName = cladeName
		colorCollapsedNode(cladeRoot, cladeColor, cladeBackgroundTextColor)

		cladeRoot.img_style["draw_descendants"] = False

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
def getCollapsedTreeStyle():
	ts = TreeStyle()
	# Do not add leaf names automatically
	ts.show_leaf_name = False
	# Use my custom layout
	ts.layout_fn = collapsedTreeLayout
	# 120 pixels per branch length unit
#	ts.scale =  120
	# Use dotted guide lines between leaves and labels
#	ts.draw_guiding_lines = True
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
	infile              = ""
	cladeFile           = ""
	cladeTreeFile       = ""
	refSeqFile          = ""
	specialAminoAcidPos = -1

	try:
		opts, args = getopt.getopt(argv,"ht:i:c:f:p:",["help", "infile=", "cladefile=", "trees=", "refSeqFile=", "specialAminoAcidPos="])
	except getopt.GetoptError as err:
		print(err, "\n")
		usage(progName)
		sys.exit(2)
	for opt, arg in opts:
		if opt == '-h':
			usage(progName)
			sys.exit()
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

	return infile, cladeFile, cladeTreeFile, refSeqFile, specialAminoAcidPos

###############################################################################

if __name__ == "__main__":
	# Execute only if run as main script

	inputTree, inputClades, cladeTreeFile, refSeqFile, specialAminoAcidPos = parseArgs(sys.argv[0], sys.argv[1:])

	isFullTree = (cladeTreeFile == "")

	if isFullTree:
		alnFile = os.path.splitext(inputTree)[0]
	else:
		alnFile = os.path.splitext(os.path.splitext(cladeTreeFile)[0])[0]

	cladeTrees             = inputTree + ".cladeTrees"
	outFullTree            = inputTree + ".fullTree.pdf"
	outFullTreeNeXML       = inputTree + ".fullTree.NeXML"
	outCollapsedTree       = inputTree + ".collapsedTree.pdf"

	formats = [3, 1]
	for f in formats:
		try:
			tree = Tree(inputTree, format=f)
			break
		except:
			continue

	for node in tree.traverse():
		node.name = node.name.replace('\'', '')

	colorMapFileName = "AminoAcidColorMap.csv"
	loadAminoAcidColors(colorMapFileName)

	if refSeqFile != "" and specialAminoAcidPos >= 0:
		determineSpecialAminoAcidsAtPos(tree, alnFile, specialAminoAcidPos, refSeqFile)
		hasSpecialAA = True

	clades = loadCladeInfo(tree, inputClades, cladeTreeFile)
	initialReroot(tree, clades)
	cladifyNodes(tree, clades)

	# Root the tree at the outgroup
	rerootToOutgroup(tree, clades)

	# Reinitialize the clades, since they were changed by rerooting
	cladifyNodes(tree, clades)
	nameCladeRoots(tree, clades)

	colorAndNameClades(tree, clades)

	if isFullTree:
		saveCladesAsTrees(tree, clades, cladeTrees)

	# We must copy the tree here, since the render function adds faces we cannot remove
	# and would still show up at the second rendering
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

	collapseTree(tree, clades)
	

	ts = getCollapsedTreeStyle()
	tree.render(outCollapsedTree, dpi=600, w=400, units="mm", tree_style=ts)

###############################################################################
