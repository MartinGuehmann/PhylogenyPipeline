# The Phylogeny Pipeline

This is the phylogeny pipeline, which builds single gene pyhlogenies for given bait sequences.

## Databases

The phylogeny pipeline downloads the uniprot protein databases sprot and trembl in fasta format and builds from them blast databases, which requires about 210 GB as of August 2021.

If you want to use newer versions you have to delete them. The databases are in ./PhylogenyPipeline/ProteinDatabase/. There, just delete the folders uniprot_trembl and uniprot_sprot.

The phylogeny pipeline also downloads the taxon database from NCBI. If you want to use a newer version just delete it. The files are in ./PhylogenyPipeline/SpeciesDatabase/.
