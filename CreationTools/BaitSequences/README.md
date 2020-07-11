## Tools to get the opsin bait sequences

The bait sequences were pick from an phylogenetic opsin tree from Ramirez et al. (2016) The sequences were chosen to represent the whole range of opsins within the tree. The sequences were annotated with the the species name and the gene name derived from the database entry, which may be incorrect. This version of the tree can be found here:

https://github.com/MartinGuehmann/PIA2/blob/ade07a8349b4bcb0aca470b9fd921a1cc57154d8/pia/LIT_1.1/opsin/ramirez_opsin_opsin.tre

# OpsinBait.csv and OpsinBait.txt

OpsinBait.csv contains the annotated IDs picked from the tree of Ramirez et al. The IDs mostly are UniProt And UniProtTRMBL IDs. Two are also UniParc IDs. OpsinBait.txt is a reduced version of OpsinBait.csv. It contains a comma seperated list of the sequence IDs from OpsinBait.csv without annotation.

# DownloadOpsinBaitSequences.sh and OpsinBait.fasta

DownloadOpsinBaitSequences.sh downloads the sequences for the IDs in OpsinBait.txt from NCBI and writes them to OpsinBaitSequences.fasta. However, OpsinBaitSequences.fasta only contains the sequences from Uniprot, but not from UniProtTRMBL. Therefore, the sequence IDs from OpsinBait.txt were used to obtain the sequences from https://www.uniprot.org/uploadlists/, by mapping from "UniProtKB AC/ID" to "UniProtKB" or from "UniParc" to "UniParc". The sequences were saved in OpsinBait.fasta, which was split with seqkit (Shen et al., 2016) into single files, one file for each sequence. The command was:

´´´seqkit split -i OpsinBait.fasta´´´

# RenameBaitFiles.sh

The files from seqkit where renamed with RenameBaitFiles.sh and OpsinBait.csv so the files have meaningful names.

# End

Originally, all these files were in the main directory.

# Literature

Ramirez, M. D., Pairett, A. N., Pankey, M. S., Serb, J. M., Speiser, D. I., Swafford, A. J., & Oakley, T. H. (2016). The last common ancestor of most bilaterian animals possessed at least nine opsins. Genome Biology and Evolution, 8(12), 3640–3652. https://doi.org/10.1093/gbe/evw248

Shen, W., Le, S., Li, Y., & Hu, F. (2016). SeqKit: A cross-platform and ultrafast toolkit for FASTA/Q file manipulation. PLoS ONE, 11(10), 1–10. https://doi.org/10.1371/journal.pone.0163962
