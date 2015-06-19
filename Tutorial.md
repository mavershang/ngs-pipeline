## Tutorial ##

### Submitting job ###
```
perl /data/software/pipeline/ngs-pipeline.pl --config config.xml --mode ALL --rerun both
```
### Removing temporary files ###
```
perl /data/software/pipeline/ngs-pipeline.pl --config config.xml --mode CLEAN --rerun both
```
### Result files ###
DIR - project directory,
PROJECT - project name
(see config.xml for configuring)
| **File** | **Description** |
|:---------|:----------------|
| DIR/PROJECT.bam.dedup.bam | whole genome alignment |
| DIR/PROJECT.variations.vcf.phased.vcf.filtered.vcf.annotated.vcf.annotated.vcf | SNPs and indels |
| DIR/PROJECT.bam.dedup.bam.cfg.max | [BreakDancer](http://breakdancer.sourceforge.net/) result |