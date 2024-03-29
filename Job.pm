package Job;
use strict;
use Program;
use Data::Dumper;

sub new {
	my ( $class, %params ) = @_;
	my $self = {};

	my %all_params = ( %{ $params{params} }, %params );
	while ( my ( $key, $value ) = each %all_params ) {
		$self->{$key} = $value;
	}
	bless $self, $class;
	$self->string_id($class);
	$self->{output_by_type} = {};
	$self->{do_not_delete}  = [];
	$self->{active}         = 0;
	$self->{next}           = [];
	my $program = $self->program ? $self->program : Program->new();
	$self->program($program);
	$self->program->additional_params( $self->{additional_params} )
	  if $self->{additional_params};
	$self->program->basic_params( $self->{basic_params} )
	  if $self->{basic_params};
	$self->manager()->register($self);
	$self->out( $params{out} ) if $params{out};
	$self->in( $params{in} )   if $params{in};
	$self->bam( $params{bam} ) if $params{bam};
	$self->memory(1);
	$self->initialize();
	return $self;
}

sub AUTOLOAD {
	my $self = shift;
	die "the subroutine doesn't exist\n";
}

sub previous {
	my ( $self, $previous ) = @_;
	$self->{previous} = $previous if $previous;
	return $self->{previous};
}

sub next {
	my ( $self, $next ) = @_;
	push( @{ $self->{next} }, $next ) if $next;
	return $self->{next};
}

sub first_previous {
	my ( $self, ) = @_;
	return ${ $self->{previous} }[0];
}

#@Override
sub initialize {
	my ( $self, ) = @_;
}

#@Override
sub output_files {
	my ( $self, ) = @_;
	return [values %{$self->{output_by_type}}];
}

sub program {
	my ( $self, $program ) = @_;
	$self->{program} = $program if $program;
	return $self->{program};
}

sub do_not_delete {
	my ( $self, $do_not_delete ) = @_;
	push( @{ $self->{do_not_delete} }, $self->output_by_type($do_not_delete) );
	return @{ $self->{do_not_delete} } unless $do_not_delete;
}

sub params {
	my ( $self, $params ) = @_;
	$self->{params} = $params if $params;
	return $self->{params};
}

sub manager {
	my ( $self, $manager ) = @_;
	$self->{manager} = $manager if $manager;
	return $self->{manager};
}

sub last_job {
	my ( $self, $last_job ) = @_;
	$self->{last_job} = $last_job if $last_job;
	return $self->{last_job};
}

sub output_by_type {
	my ( $self, $type, $output ) = @_;
	$self->{output_by_type}->{$type} = $output if $output;
	return $self->{output_by_type}->{$type};
}

sub out {
	my ( $self, $output ) = @_;
	$self->{output_by_type}->{main} = $output if $output;
	return $self->{output_by_type}->{main};
}

sub get_output_files {
	my ( $self, ) = @_;
	my @files;
	while ( ( my $key, my $value ) = each %{ $self->{output_by_type} } ) {
		push( @files, $value );
	}
	return @files;
}

sub in {
	my ( $self, $in ) = @_;
	$self->{in} = $in if $in;
	return $self->{in};
}

sub bam {
	my ( $self, $bam ) = @_;
	$self->{bam} = $bam if $bam;
	return $self->{bam};
}

sub project {
	my ( $self, $project ) = @_;
	$self->{project} = $project if $project;
	return $self->{project};
}

sub scheduler {
	my ( $self, $scheduler ) = @_;
	$self->{scheduler} = $scheduler if $scheduler;
	return $self->{scheduler};
}

sub string_id {
	my ( $self, $string_id ) = @_;
	$self->{string_id} = $string_id if $string_id;
	return $self->{string_id};
}

sub name {
	my ( $self, ) = @_;
	return $self->string_id();
}

sub active {
	my ( $self, $active ) = @_;
	$self->{active} = $active if $active;
	return $self->{active};
}

sub submit {
	my ( $self, ) = @_;
	unless ( $self->virtual() ) {
		if ( !$self->completed ) {
			$self->active(1);
		}
		$self->scheduler()->submit_job($self) if $self->active();
	}
	$self->activize_descendents() if $self->active();
}

sub activize_descendents {
	my ( $self, ) = @_;
	my $descendents = $self->next();
	for my $descendent (@$descendents){
		$descendent->active(1);
	}
}

sub completed {
	my ( $self, ) = @_;
	return 1 if $self->virtual;
	my $rerun = $self->{rerun};
	if ( $rerun eq 'out' ) {
		return 1 if -s $self->out;
	}
	elsif ( $rerun eq 'done' ) {
		return 1 if -s $self->_done_name;
	}
	elsif ( $rerun eq 'both' ) {
		return 1 if ( ( -s $self->out ) && ( -s $self->_done_name ) );
	}
	else{
		warn "You should specify --rerun option.\nAvailable options are: out, done, both.\n";
		exit 0;
	}
	return 0;
}

sub has_unfinished_predessesors {
	my ( $self, ) = @_;
	return 0 unless $self->previous;
	for my $job ( @{ $self->previous } ) {
		if ( $job->completed ) {
			if ( $job->has_unfinished_predessesors ) {
				return 1;
			}
		}
		else {
			return 1;
		}
	}
	return 0;
}

sub qsub_params {
	my ( $self, $qsub_params ) = @_;
	$self->{qsub_params} = $qsub_params if $qsub_params;
	return $self->{qsub_params};
}

sub virtual {
	my ( $self, $virtual ) = @_;
	$self->{virtual} = $virtual if $virtual;
	return $self->{virtual};
}

sub memory {
	my ( $self, $memory ) = @_;
	$self->program->memory($memory) if $memory;
	return $self->program->memory;
}

sub processors {
	my ( $self, $processors ) = @_;
	$self->{processors} = $processors if $processors;
	return $self->{processors};
}

#@Override
sub status {
	my ( $self, ) = @_;
}

####################################################

#folders

sub task_id_file {    #fixed
	my ( $self, ) = @_;
	my $job_name = $self->job_name();
	return $self->project()->ids_dir() . "/$job_name.id";
}

sub job_id {
	my ( $self, ) = @_;
	return undef if $self->virtual;
	my $file = $self->task_id_file();
	return $self->get_sge_id($file);
}

sub get_sge_id {
	my ( $self, $file ) = @_;
	if ( $self->project()->{'DEBUG'} ) {
		$file = "id.txt";
	}
	open IN, "<$file" or return undef;
	while (<IN>) {
		return $1 if m/Your job\s(\d+)\s/;
	}
	close IN;
}

sub file_prefix {
	my ($self) = @_;
	return $self->{'CONFIG'}->{'DIR'} . '/' . $self->{'CONFIG'}->{'PROJECT'};
}

sub tmp_dir {
	my ($self) = @_;
	return $self->project()->dir;
}

sub get_out_by_suffix {
	my ( $self, $suffix ) = @_;
	return $self->file_prefix() . ".$suffix";
}

sub get_job_by_suffix {
	my ( $self, $suffix ) = @_;
	return "$suffix." . $self->_get_id( $self->get_out_by_suffix($suffix) );
}

sub job_name {
	my ($self) = @_;
	unless($self->out()){
		warn ("Job: ", $self->string_id(), " doesn't have output file name\n");
	} 
	return $self->string_id() . "_" . $self->_get_id( $self->out() );
}

sub _get_id {
	my ( $self, $file ) = @_;
	$file =~ s/\//_/g;
	$file =~ s/\://g;
#	$file .= "_" . $self->project()->{'TIME'};
	return $file;
}

sub command {
	my ( $self, $command ) = @_;
	if ( $self->{'DEBUG'} ) {
		print "$command\n";
	}
	else {
		system("echo $command");
		system("$command");
	}
}

sub get_all_ids {
	my ($self) = @_;
	my $dir    = $self->ids_dir();
	my @files  = <$dir/*>;
	my @ids;
	for my $file (@files) {
		push( @ids, $self->get_sge_id($file) );
	}
	return \@ids;
}

sub read_intervals {
	my ($self) = @_;
	my $file = $self->{'CONFIG'}->{'GATKGENOMEBED'};
	my @data;
	open IN, $file or die "Can't open $file\n";
	while (<IN>) {
		chomp;
		next if m/GL/;
		push( @data, "$1" ) if m/(.+)\t(\d+)\t(\d+)/;
	}
	close IN;
	return @data;
}

sub _script_name {
	my ( $self, ) = @_;
	my $job_name = $self->job_name;
	return $self->project->script_dir() . "/task.$job_name.script";
}

sub _date_name {
	my ( $self, $job_name ) = @_;
	my $name = $self->job_name;
	return $self->project->script_dir() . "/task.$name.date";
}

sub _done_name {
	my ( $self, $job_name ) = @_;
	my $name = $self->job_name;
	return $self->project->script_dir() . "/task.$name.done";
}

sub output_name {
	my ( $self, $job_name ) = @_;
	my $name = $self->job_name;
	return $self->project->output_dir() . "/$name.o";
}

sub error_name {
	my ( $self, $job_name ) = @_;
	my $name = $self->job_name;
	return $self->project->error_dir() . "/$name.e";
}

return 1;
