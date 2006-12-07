#!/usr/local/bin/perl

=head1 NAME

vega_gene_density.pl - script to calculate gene densities and stats in Vega

=head1 SYNOPSIS

vega_gene_density.pl [options]

General options:
    --conffile, --conf=FILE             read parameters from FILE
                                        (default: conf/Conversion.ini)

    --dbname, db_name=NAME              use database NAME
    --host, --dbhost, --db_host=HOST    use database host HOST
    --port, --dbport, --db_port=PORT    use database port PORT
    --user, --dbuser, --db_user=USER    use database username USER
    --pass, --dbpass, --db_pass=PASS    use database passwort PASS
    --logfile, --log=FILE               log to FILE (default: *STDOUT)
    --logpath=PATH                      write logfile to PATH (default: .)
    --logappend, --log_append           append to logfile (default: truncate)
    -v, --verbose                       verbose logging (default: false)
    -i, --interactive=0|1               run script interactively (default: true)
    -n, --dry_run, --dry=0|1            don't write results to database
    -h, --help, -?                      print help (this message)

Specific options:

    --chromosomes, --chr=LIST           only process LIST chromosomes
    --prune								delete data in the database from a previous run
    --limit_file                        only process gene_ids in this file

=head1 DESCRIPTION

This script calculates Vega gene densities and total numbers per chromosome
for use in mapview. It also checks for new biotype/status pairs and warns to
adapt the appropriate modules to deal with them.

The block size is determined so that you have 150 bins for the smallest
chromosome over 5 Mb in length. For chromosomes smaller than 5 Mb, an
additional smaller block size is used to yield 150 bins for the overall
smallest chromosome. This will result in reasonable resolution for small
chromosomes and high performance for big ones.

=head1 LICENCE

This code is distributed under an Apache style licence:
Please see http://www.ensembl.org/code_licence.html for details

=head1 AUTHOR

Patrick Meidl <pm2@sanger.ac.uk>

based on code by
    Graham McVicer <mcvicker@ebi.ac.uk>
    Steve Trevanion <st3@sanger.ac.uk>

=head1 CONTACT

Post questions to the EnsEMBL development list ensembl-dev@ebi.ac.uk

=cut

use strict;
use warnings;
no warnings 'uninitialized';

use FindBin qw($Bin);
use vars qw($SERVERROOT);

BEGIN {
    $SERVERROOT = "$Bin/../../..";
    unshift(@INC, "$SERVERROOT/ensembl/modules");
    unshift(@INC, "$SERVERROOT/bioperl-live");
}

use Getopt::Long;
use Pod::Usage;
use Bio::EnsEMBL::Utils::ConversionSupport;
use Bio::EnsEMBL::DensityType;
use Bio::EnsEMBL::DensityFeature;
use POSIX;

$| = 1;

my $support = new Bio::EnsEMBL::Utils::ConversionSupport($SERVERROOT);

# parse options
$support->parse_common_options(@_);
$support->parse_extra_options('chromosomes|chr=s@', 'prune', 'limit_file=s');
$support->allowed_params($support->get_common_params, 'chromosomes', 'prune', 'limit_file');

if ($support->param('help') or $support->error) {
    warn $support->error if $support->error;
    pod2usage(1);
}

$support->comma_to_list('chromosomes');

# ask user to confirm parameters to proceed
$support->confirm_params;

# get log filehandle and print heading and parameters to logfile
$support->init_log;

# connect to database and get adaptors
my $dba = $support->get_database('ensembl');
my $slice_adaptor = $dba->get_SliceAdaptor;
my $dfa = $dba->get_DensityFeatureAdaptor;
my $dta = $dba->get_DensityTypeAdaptor;
my $aa = $dba->get_AnalysisAdaptor;
my $attrib_adaptor = $dba->get_AttributeAdaptor;
my $dbh = $dba->dbc->db_handle;


# split chromosomes by size and determine block size
my $chr_slices = $support->split_chromosomes_by_size(5000000);

# known biotype/status pairs and associated density type

# Note: the types starting with 'total_...' should only be used for the stats stuff and are composed of other types, 
# which are in the array pointed to by the 'parts' key


my %gene_types= (
	"protein_coding_KNOWN" => {logic_name => "knownPCodDensity", code => "KnownPCCount", description => "Number of Known Protein Coding"},
	"protein_coding_in_progress_KNOWN" => {logic_name => "knownPCodDensity", code => "KnwnPCProgCount", description => "Number of Known Protein coding genes in progress" },
	"processed_transcript_KNOWN"  => {logic_name => "knownPTransDensity", code => "KnownPTCount", description => "Number of Known Processed Transcripts" },
	"protein_coding_NOVEL"  => {logic_name => "novelPCodDensity", code => "NovelPCCount", description => "Number of Novel Protein Coding"},
	"protein_coding_in_progress_NOVEL" => {logic_name => "novelPCodDensity", code => "NovPCProgCount", description => "Number of Novel Protein coding genes in progress"},
	"processed_transcript_NOVEL" => {logic_name => "novelPTransDensity", code => "NovelPTCount", description => "Number of Novel transcripts"},
	"processed_transcript_PUTATIVE" => {logic_name => "putativePTransDensity", code => "PutPTCount", description => "Number of Putative processed transcripts"},
	"protein_coding_PREDICTED" => {logic_name => "predictedPCodDensity", code => "PredPCCount", description => "Number of Predicted transcripts"},
	"Ig_pseudogene_segment_UNKNOWN"  => {logic_name => "IgPseudoSegDensity", code => "IgPsSegCount", description => "Number of Ig Pseudogene Segments"},
	"Ig_segment_NOVEL" => {logic_name => "IgSegDensity", code => "", description => ""},
	"Ig_segment_KNOWN"  => {logic_name => "IgSegDensity", code => "", description => ""},
	"pseudogene_UNKNOWN" => {logic_name => "pseudoGeneDensity", code => "", description => ""},
	"processed_pseudogene_UNKNOWN" => {logic_name => "pseudoGeneDensity", code => "ProcPsCount", description => "Number of Processed pseudogenes"},
	"unprocessed_pseudogene_UNKNOWN" => {logic_name => "pseudoGeneDensity", code => "UnprocPsCount", description => "Number of Unprocessed pseudogenes"},
	"total_pseudogene_UNKNOWN" => {logic_name => "", code => "TotPsCount", description => "Total Number of Pseudogenes", parts => ['pseudogene_UNKNOWN', 'processed_pseudogene_UNKNOWN', 'unprocessed_pseudogene_UNKNOWN']},
	"total_Ig_segment_UNKNOWN" => {logic_name => "", code => "IgSegCount", description => "Number of Ig Segments", parts => ['Ig_segment_NOVEL','Ig_segment_KNOWN']},
	"processed_transcript_UNKNOWN"     => {logic_name => "PTransDensity", code => "PTCount", description => "Number of Processed Transcripts"},
    "processed_transcript_PREDICTED"   => {logic_name => "PredPTransDensity", code => "PredPTCount", description => "Number of Predicted Processed Transcripts"}
);

if($support->param('prune')){
	# delete the results in the database from a previous run
	
	$support->log("running in prune mode\n");
	$support->log("pruning 1 (tables analysis, density_type, density_feature)\n");
	
	# Note: Need to use a left-join in the multitable delete otherwise rows in e.g. analysis which have program= vega_gene_density.pl, but no corresponding rows in the density_type or density_feature table will NOT be deleted.
	
	my $query= "delete analysis, density_type, density_feature from analysis left join density_type on analysis.analysis_id= density_type.analysis_id left join density_feature on density_type.density_type_id= density_feature.density_type_id where analysis.program= 'vega_gene_density.pl'";


	if($dbh->do($query)){

		$support->log("prune 1 was successfull: any previous entries in the database generated by this script have been deleted\n");

	}
	else{

		$support->log_error("prune 1 failed: any previous entries in the database generated by this script have NOT been deleted\n");
	}

	
	foreach my $name(keys %gene_types){
		
		my $href= $gene_types{$name};
		my $code= $href->{'code'};
		
		if($code){
			#$query= "delete attrib_type, seq_region_attrib from attrib_type, seq_region_attrib where (attrib_type.code= '$code') and (attrib_type.attrib_type_id= seq_region_attrib.attrib_type_id)";
			$query= "delete attrib_type, seq_region_attrib from attrib_type left join seq_region_attrib on attrib_type.attrib_type_id= seq_region_attrib.attrib_type_id where attrib_type.code= '$code'";
			if($dbh->do($query)){

				$support->log("prune 2 was successfull for code $code\n");
		
			}
			else{
		
				$support->log_error("prune 2 failed for code $code\n");
			}
				
		
		}
	
	
	
	}
	
	
	
	
	
	
	$support->finish_log;
	exit;
	

}

#limit to gene_stable_ids ?
my (%gene_ids, %found_genes);
if ($support->param('limit_file')) { 
	my $in = $support->filehandle('<', $support->param('limit_file'));
	while (<$in>) {
		my ($gsi) = split ' ', $_;
		$gene_ids{$gsi}++;
	}
}


# check for new biotype/status pairs
my $sql = qq(
    SELECT biotype, status
    FROM gene
    GROUP by biotype, status
);
my $sth = $dbh->prepare($sql);
$sth->execute;
my (%type_status, $new);
while (my ($biotype, $status) = $sth->fetchrow_array) {
	my $type = $biotype.'_'.$status;
    if ($gene_types{$type}) {
        $type_status{$type} = 'no';
    } else {
        $type_status{$type} = 'YES';
        $new = 1;
    }
}
my $FMT = "%-50s%-20s\n";
$support->log("Checking for new biotype/status pairs...\n\n");
$support->log(sprintf($FMT, qw(BIOTYPE/STATUS NEW)), 1);
$support->log(('-'x70)."\n", 1);
map { $support->log(sprintf($FMT, $_, $type_status{$_}), 1) }
    sort keys %type_status;
$support->log("\n");
if ($new) {
    $support->log_warning("There are new biotype/status pairs! You might need to adapt Bio::EnsEMBL::ColourMap, EnsEMBL::Sanger_vega::Component::Chromosome and configure mapview to show them.\n\n");
}


# create Analysis and DensityType objects
my (%density_types, $dtcache);
foreach my $type (keys %gene_types) {
    
    # ignore any type starting with 'total_'
    if($type =~/^total_/){
    
    	next;
    }
    
    
    $density_types{$gene_types{$type}{'logic_name'}} = 1;
    my $analysis = new Bio::EnsEMBL::Analysis (
        -program     => "vega_gene_density.pl",
        -database    => "ensembl",
        -gff_source  => "vega_gene_density.pl",
        -gff_feature => "density",
        -logic_name  => $gene_types{$type}{'logic_name'}
    );
    $aa->store($analysis) unless ($support->param('dry_run'));
    foreach my $block_size (keys %{ $chr_slices }) {
        my $dt = Bio::EnsEMBL::DensityType->new(
            -analysis   => $analysis,
            -block_size => $block_size,
            -value_type => 'sum'
        );
        $dta->store($dt) unless ($support->param('dry_run'));
        $dtcache->{$block_size}->{$gene_types{$type}{'logic_name'}} = $dt;
    }
}

# loop over block sizes
foreach my $block_size (keys %{ $chr_slices }) {
    $support->log("Available chromosomes using block size of $block_size:\n    ");
    $support->log(join("\n    ", map { $_->seq_region_name } @{ $chr_slices->{$block_size} })."\n");

    # looping over chromosomes
    $support->log_stamped("\nLooping over chromosomes...\n");
    my ($current_start, $current_end);
    foreach my $slice (@{ $chr_slices->{$block_size} }) {
        $current_start = 1;
        my $chr = $slice->seq_region_name;
        my (%total, $i, %gene_names);
        my $bins = POSIX::ceil($slice->end/$block_size);
        
        $support->log_stamped("Chromosome $chr with block size $block_size...\n", 1);
        
        # loop over blocks
        my @density_features;
        while($current_start <= $slice->end) {
            $i++;
            $current_end = $current_start + $block_size - 1;
            if ($current_end > $slice->end) {
                $current_end = $slice->end;
            }
            my $sub_slice = $slice->sub_Slice($current_start, $current_end);
            my %num = ();
            
            # count genes by type
            my $genes;
            eval { $genes = $sub_slice->get_all_Genes; };
            if ($@) {
                $support->log_warning("$@");
                $current_start = $current_end + 1;
                next;
            }
           GENE: foreach my $gene (@{$genes}) {
           
           		if ($support->param('limit_file')) {
					my $gsi = $gene->stable_id;
					next GENE unless ($gene_ids{$gsi});
					$gene_ids{$gsi} |= 2;
				}
				
                # only count genes that don't overlap the subslice start
                # (since these were already counted in the last bin)
                my $gene_type = $gene->biotype . '_' . $gene->status;
                if ($gene->start >= 1) {
                    $total{$gene_type}++;
                }
                $num{$gene_types{$gene_type}{'logic_name'}}++;
            }
            
            # create DensityFeature objects for each type
            foreach my $type (keys %density_types) {
                push @density_features, Bio::EnsEMBL::DensityFeature->new(
                    -seq_region    => $slice,
                    -start         => $current_start,
                    -end           => $current_end,
                    -density_type  => $dtcache->{$block_size}->{$type},
                    -density_value => $num{$type} || 0
                );
            }
            $current_start = $current_end + 1;
            
            # logging
            $support->log_verbose("Chr: $chr | Bin: $i/$bins | Counts: ".
                join(",", map { $num{$gene_types{$_}{'logic_name'}} || 0 }
                    sort keys %gene_types)."\n", 2);
        }
        
        # store DensityFeatures for the chromosome
        $dfa->store(@density_features) unless ($support->param('dry_run'));
        
        # stats
        my @attribs;
        
        foreach my $name(keys %gene_types){
        
        	my $href= $gene_types{$name};
        	
        	my $code= $href->{'code'};
        	next unless $code;
        	
        	
        	my $description= $href->{'description'};
        	my $value=0;
        	
        	if(exists $href->{'parts'}){
        		#contains multiple elements
        		
        		
        		foreach my $part($href->{'parts'}){
        		
        			$value += $total{$part} || 0;
        		
        		
        		}
        		
        	
        	}else{
        	
        		#contains a single element
        		$value= $total{$name} || 0;
        		
        	}
        	
        	push @attribs, Bio::EnsEMBL::Attribute->new(
	            -NAME => $name,
	            -CODE => $code,
	            -VALUE => $value,
	            -DESCRIPTION => $description
	        );
        
        }
        
       
        

        $attrib_adaptor->store_on_Slice($slice, \@attribs) unless ($support->param('dry_run'));
        
        # log stats
        $support->log("\n");
        $support->log("Totals for chr $chr:\n", 1);
        $support->log(sprintf($FMT, qw(TYPE COUNT)), 2);
        $support->log(('-'x70)."\n", 2);
        map { $support->log(sprintf($FMT, $_, $total{$_}), 2) } sort keys %total;
        $support->log_stamped("\nDone.\n\n", 1);
    }
    $support->log_stamped("Done.\n");
}

if (%gene_ids) {
	my $no_genes_to_look_for = keys %gene_ids;
	my (@genes_not_found) = grep {$gene_ids{$_} == 1} keys %gene_ids;
	$support->log("Of the $no_genes_to_look_for genes in ".$support->param('limit_file')." , the following were missing: @genes_not_found\n");
}

$support->log_stamped("Done.\n");

# finish logfile
$support->finish_log;

