cd $1

git add AlignmentFiles.txt
git add SequenceFiles.txt
# Don't add, too big
#git add SequencesOfInterestShuffled.part_*.fasta
git add SequencesOfInterestShuffled.part_*.fasta.raxml.log
git add SequencesOfInterestShuffled.part_*.fasta.raxml.reduced.phy
git add SequencesOfInterestShuffled.part_*.fasta.raxml.reduced.phy.bionj
git add SequencesOfInterestShuffled.part_*.fasta.raxml.reduced.phy.ckp.gz
git add SequencesOfInterestShuffled.part_*.fasta.raxml.reduced.phy.contree
git add SequencesOfInterestShuffled.part_*.fasta.raxml.reduced.phy.iqtree
git add SequencesOfInterestShuffled.part_*.fasta.raxml.reduced.phy.log
# Don't add too big
#git add SequencesOfInterestShuffled.part_*.fasta.raxml.reduced.phy.mldist
git add SequencesOfInterestShuffled.part_*.fasta.raxml.reduced.phy.model.gz
git add SequencesOfInterestShuffled.part_*.fasta.raxml.reduced.phy.splits.nex
git add SequencesOfInterestShuffled.part_*.fasta.raxml.reduced.phy.treefile

# Don't add to big
#git add SequencesOfInterestShuffled.part_*.fasta.raxml.reduced.phy.ufboot

git add SequencesOfInterestShuffled.part_*.err.txt
git add SequencesOfInterestShuffled.part_*.fasta
git add SequencesOfInterestShuffled.part_*.out.txt
git add SequencesOfInterestShuffled.part_*.score.txt
git add SequencesOfInterestShuffled.part_*.tre

# The glob also covers this so remove this again
git rm --cache SequencesOfInterestShuffled.part_*.alignment.*.fasta
