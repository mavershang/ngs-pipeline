use strict;
use lib qw(/data/software/pipeline/);
use ConfigRun;
use Project;
use TaskScheduler;
use Time::HiRes qw ( time sleep);
use Data::Dumper;

####### general parameters ###
my $config = ConfigRun->new( $ARGV[0] );
my $debug  = $ARGV[1] ? $ARGV[1] : 0;

my $project        = Project->new( $config,        $debug );
my $task_scheduler = TaskScheduler->new( $project, $debug );

#my $email = $config->{'EMAIL'};
#my $config_dir = $config->{'DIR'};
my $proc         = 4;    #number of processos for running bwa
my $sleep_time   = 0;
my $bwa_priority = 10;

# making right folder structure
my $script_dir = $config->{'DIR'} . '/tasks';
$project->make_folder_structure();
##############################

#bwa commands
my $bwa    = $config->{'BWA'} . "/bwa";
my $mpirun = $config->{'MPIRUN'} . "/mpirun -np $proc";
my $align  = "$bwa aln -t $proc";
my $sampe  = "$bwa sampe";
my $samse  = "$bwa samse";

#samtools commands
my $samtools  = $config->{'SAMTOOLS'} . "/samtools";
my $import    = "$samtools import";
my $sort      = "$samtools sort";
my $index     = "$samtools index";
my $merge     = "$samtools merge";
my $gatk      = $config->{'GATK'} . "/GenomeAnalysisTK.jar";
my $call      = "";
my $genome    = $config->{'GENOME'};
my $gene_list = $config->{'GENELIST'};
my $effect    =
  $config->{'VCFCODINGSNPS'} . "/vcfCodingSnps.v1.5 -r $genome -g $gene_list";
my $filter_interesting = "perl /data/software/filter_interesting.pl";
my $genome_coverage    = $config->{'BEDTOOLS'} . "/genomeCoverageBed";

####### commands to execute ##

for my $lane ( @{ $config->{LANES} } ) {
	align( $project, $lane );
	sai_to_sam( $project, $lane );
	import_sam( $project, $lane );
	sort_bam( $project, $lane );
	index_bam( $project, $lane );

}
merge_bams($project);
sort_merged($project);
index_merged($project);
call_SNPs($project);
predict_effect($project);
callable_loci($project);

#depth_coverage($project);
calculate_genome_coverage($project);
calculate_bga_coverage($project);
move_bedtools_results($project);
filter_snps($project);

#clean($project);

#get_target_SNPs($project);
#calculate_coverage($project);
#write_report($project);

sub align {
	my ( $project, $lane ) = @_;
	sleep($sleep_time);

	submit_alignment(
		$project->reverse_name($lane),
		$project->reverse_sai($lane),
		$project->reverse_align_id($lane)
	);

	if ( $lane->{'PAIRED'} ) {
		submit_alignment(
			$project->forward_name($lane),
			$project->forward_sai($lane),
			$project->forward_align_id($lane)
		);
	}
}

sub sai_to_sam {
	my ( $project, $lane ) = @_;
	sleep($sleep_time);
	my $forward_reads = $project->forward_name($lane);
	my $reverse_reads = $project->reverse_name($lane);
	my $forward_sai   = $project->forward_sai($lane);
	my $reverse_sai   = $project->reverse_sai($lane);
	my $sam           = $project->sam($lane);
	my $program       = "";
	my $qsub_param    = "";
	if ( $lane->{'PAIRED'} ) {
		$program =
"$sampe -f $sam $genome $forward_sai $reverse_sai $forward_reads $reverse_reads";
		$qsub_param =
		    '-hold_jid '
		  . $project->task_id( $project->forward_align_id($lane) ) . ','
		  . $project->task_id( $project->reverse_align_id($lane) );
	}
	else {
		$program =
"$samse -f $sam $genome $reverse_sai $reverse_reads";
		$qsub_param =
		    '-hold_jid '
		  . $project->task_id( $project->forward_align_id($lane) ) . ','
		  . $project->task_id( $project->reverse_align_id($lane) );
	}
	$task_scheduler->submit( $project->sam_id($lane), $qsub_param, $program );
}

sub import_sam {
	my ( $project, $lane ) = @_;
	sleep($sleep_time);
	my $sam        = $project->sam($lane);
	my $bam        = $project->bam($lane);
	my $program    = "$import $genome.fai $sam $bam";
	my $qsub_param =
	  '-hold_jid ' . $project->task_id( $project->sam_id($lane) );
	$task_scheduler->submit( $project->import_id($lane), $qsub_param,
		$program );
}

sub sort_bam {
	my ( $project, $lane ) = @_;
	sleep($sleep_time);
	my $bam           = $project->bam($lane);
	my $sorted_prefix = $project->sorted_prefix($lane);
	my $program       = "$sort $bam $sorted_prefix";
	my $qsub_param    =
	  '-hold_jid ' . $project->task_id( $project->import_id($lane) );
	$task_scheduler->submit( $project->sorted_id($lane), $qsub_param,
		$program );
}

sub index_bam {
	my ( $project, $lane ) = @_;
	sleep($sleep_time);
	my $sorted     = $project->sorted($lane);
	my $program    = "$index $sorted";
	my $qsub_param =
	  '-hold_jid ' . $project->task_id( $project->sorted_id($lane) );
	$task_scheduler->submit( $project->index_id($lane), $qsub_param, $program );
}

sub submit_alignment {
	my ( $in, $out, $job_id ) = @_;
	sleep($sleep_time);
	my $program    = "$align -f $out $genome $in";
	my $qsub_param = "-pe mpi $proc -p $bwa_priority";
	$task_scheduler->submit( $job_id, $qsub_param, $program );
}

sub merge_bams {
	my ($project) = @_;
	sleep($sleep_time);
	my $lanes = $project->{'CONFIG'}->{'LANES'};
	my @lane_bams;
	for my $lane (@$lanes) {
		my $file = $project->bam($lane);
		push( @lane_bams, $file );
	}
	my $all_bams = join( ' ', @lane_bams );
	my $program = "$merge " . $project->merged() . " $all_bams";
	if ( scalar @lane_bams == 1 ) {
		my $lb = $lane_bams[0];
		$program = "/bin/cp $lb " . $project->merged();
	}
	my $qsub_param = '-hold_jid ' . $project->all_indexed_ids();
	$task_scheduler->submit( $project->merged_id(), $qsub_param, $program );
}

sub sort_merged {
	my ($project) = @_;
	sleep($sleep_time);
	my $merged        = $project->merged();
	my $sorted_prefix = $project->merged_sorted_prefix();
	my $program       = "$sort $merged $sorted_prefix";
	my $qsub_param = '-hold_jid ' . $project->task_id( $project->merged_id() );
	$task_scheduler->submit( $project->merged_sorted_id(),
		$qsub_param, $program );
}

sub index_merged {
	my ($project) = @_;
	sleep($sleep_time);
	my $merged     = $project->merged_sorted();
	my $program    = "$index $merged";
	my $qsub_param =
	  '-hold_jid ' . $project->task_id( $project->merged_sorted_id() );
	$task_scheduler->submit( $project->merged_indexed_id(),
		$qsub_param, $program );
}

sub call_SNPs {
	my ($project) = @_;
	sleep($sleep_time);
	my $merged   = $project->merged_sorted();
	my $gatk_vcf = $project->gatk_vcf();
	my $id       = $project->{'CONFIG'}->{'PROJECT'};
	my $dbSNP    = $project->{'CONFIG'}->{'DBSNP'};
	my $program  = <<PROGRAM;
java -jar $gatk -R $genome -T UnifiedGenotyper -I $merged -B:dbsnp,VCF $dbSNP -o $gatk_vcf \\
-stand_call_conf 50.0 \\
-stand_emit_conf 10.0 \\
-dcov 50 -U \\
--assume_single_sample_reads $id \\
--platform SOLEXA
PROGRAM

	my $qsub_param =
	  '-hold_jid ' . $project->task_id( $project->merged_indexed_id() );
	$task_scheduler->submit( $project->gatk_vcf_id(), $qsub_param, $program );
}

sub callable_loci {
	my ($project) = @_;
	sleep($sleep_time);
	my $merged       = $project->merged_sorted();
	my $loci         = $project->callable_loci();
	my $loci_summary = $project->callable_loci_summary();
	my $id           = $project->{'CONFIG'}->{'PROJECT'};
	my $genome_bed   = $project->{'CONFIG'}->{'GATKGENOMEBED'};
	my $program      = <<PROGRAM;
java -Xmx4g -jar $gatk -R $genome -T CallableLoci -I $merged -o $loci -l INFO -format BED -maxDepth 160 -L $genome_bed -summary $loci_summary
PROGRAM
	my $qsub_param =
	  '-hold_jid ' . $project->task_id( $project->merged_indexed_id() );
	$task_scheduler->submit( $project->callable_loci_id(),
		$qsub_param, $program );
}

sub depth_coverage {
	my ($project) = @_;
	sleep($sleep_time);
	my $merged     = $project->merged_sorted();
	my $out        = $project->depth_coverage();
	my $genome_bed = $project->{'CONFIG'}->{'GATKGENOMEBED'};
	my $program    = <<PROGRAM;
java -jar $gatk -R $genome -T DepthOfCoverage -I $merged -L $genome_bed -o $out
PROGRAM
	my $qsub_param =
	  '-hold_jid ' . $project->task_id( $project->merged_indexed_id() );
	$task_scheduler->submit( $project->depth_coverage_id(),
		$qsub_param, $program );
}

sub predict_effect {
	my ($project) = @_;
	sleep($sleep_time);
	my $gatk_vcf   = $project->gatk_vcf();
	my $eff_vcf    = $project->eff_vcf();
	my $program    = "$effect -s $gatk_vcf -o $eff_vcf -l $eff_vcf.log";
	my $qsub_param =
	  '-hold_jid ' . $project->task_id( $project->gatk_vcf_id() );
	$task_scheduler->submit( $project->eff_vcf_id(), $qsub_param, $program );
}

sub filter_snps {
	my ($project) = @_;
	sleep($sleep_time);
	my $eff_vcf    = $project->eff_vcf();
	my $filtered   = $project->filter_snps();
	my $program    = "$filter_interesting $eff_vcf $filtered";
	my $qsub_param = '-hold_jid ' . $project->task_id( $project->eff_vcf_id() );
	$task_scheduler->submit( $project->filter_snps_id(), $qsub_param,
		$program );
}

sub calculate_genome_coverage {
	my ($project) = @_;
	sleep($sleep_time);
	my $merged = $project->merged_sorted();

	#my $coverage_file = $project->genome_coverage();

	my $program =
	  "$genome_coverage -ibam $merged -g "
	  . $project->{'CONFIG'}->{'BEDGENOME'};

	my $qsub_param =
	  '-hold_jid ' . $project->task_id( $project->merged_indexed_id() );
	$task_scheduler->submit( $project->genome_coverage_id(),
		$qsub_param, $program );
}

sub calculate_bga_coverage {
	my ($project) = @_;
	sleep($sleep_time);
	my $merged = $project->merged_sorted();

	#my $coverage_file = $project->genome_coverage_bga();

	my $program =
	  "$genome_coverage -bga -ibam $merged -g "
	  . $project->{'CONFIG'}->{'BEDGENOME'};

	my $qsub_param =
	  '-hold_jid ' . $project->task_id( $project->merged_indexed_id() );
	$task_scheduler->submit( $project->genome_coverage_bga_id(),
		$qsub_param, $program );
}

sub move_bedtools_results {
	my ($project) = @_;
	sleep($sleep_time);
	my $out_dir    = $project->output_dir();
	my $genome_cov = $out_dir . '/' . $project->genome_coverage_id() . "*";
	my $bga_cov    = $out_dir . '/' . $project->genome_coverage_bga_id() . "*";
	my $program    =
	    "/bin/cp $genome_cov "
	  . $project->genome_coverage() . "\n"
	  . "/bin/cp $bga_cov "
	  . $project->genome_coverage_bga() . "\n";
	my $qsub_param =
	    '-hold_jid '
	  . $project->task_id( $project->genome_coverage_id() ) . ','
	  . $project->task_id( $project->genome_coverage_bga_id() );
	$task_scheduler->submit( $project->move_bedtools_results_id(),
		$qsub_param, $program );
}

sub clean() {
	my ($project) = @_;
	sleep($sleep_time);
	my $files_array_to_remove = $project->get_garbage_files();
	my $files_to_remove       = join( ' ', @$files_array_to_remove );
	my $program               = "/bin/rm -f $files_to_remove";
	my $qsub_param            =
	  '-hold_jid ' . $project->task_id( $project->merged_indexed_id() );
	$task_scheduler->submit( $project->clean_id(), $qsub_param, $program );
}

#
#sub get_target_SNPs{
#	my ($project) = @_;
#	my $sorted = $project->sorted($lane);
#	my $program = "$index $sorted";
#	my $qsub_param = '-hold_jid ' . $project->sorted_id($lane);
#	$task_scheduler->submit($config->{'USER'}, $project->index_id($lane), $qsub_param, $program, $email);
#
#}

#
#sub write_report{
#	my ($project) = @_;
#	my $sorted = $project->sorted($lane);
#	my $program = "$index $sorted";
#	my $qsub_param = '-hold_jid ' . $project->sorted_id($lane);
#	$task_scheduler->submit($config->{'USER'}, $project->index_id($lane), $qsub_param, $program, $email);
#
#}
