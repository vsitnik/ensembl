
#
# BioPerl module for Bio::EnsEMBL::DB::CloneI
#
# Cared for by Ewan Birney <birney@sanger.ac.uk>
#
# Copyright Ewan Birney
#
# You may distribute this module under the same terms as perl itself

# POD documentation - main docs before the code

=head1 NAME

Bio::EnsEMBL::EMBLLOAD::Clone

=head1 SYNOPSIS

    # get a clone object somehow

    @contigs = $clone->get_all_Contigs();

    @genes   = $clone->get_all_Genes();




    
=head1 DESCRIPTION

Ewan Birney

=head1 CONTACT

Describe contact details here

=head1 APPENDIX

The rest of the documentation details each of the object methods. Internal methods are usually preceded with a _

=cut


# Let the code begin...


package Bio::EnsEMBL::EMBLLOAD::Clone;
use Bio::Root::RootI;
use vars qw(@ISA);
use strict;
use Bio::EnsEMBL::EMBLLOAD::Contig;
@ISA = qw(Bio::Root::RootI Bio::EnsEMBL::DB::CloneI);
use Bio::EnsEMBL::Translation;

# Object preamble - inheriets from Bio::Root::Object

# new() is inherited from Bio::Root::Object


sub new {
    my($class,@args) = @_;    

    my $self = {};
    bless $self,$class;


    my ($annseq)=$self->_rearrange([qw(ANNSEQ)],@args);

    $self->_get_Seq($annseq);

    # HACK by th, for ensembl100:
    # store id in memory, to be changed to accession 
    # since annseq comes with id set to embl_id instead
    $self->{'_id'} = $self->_get_Seq->id;

    return $self; 
    
}



=head2 id

 Title   : id
 Usage   : this is the primary id for ensembl. General the accession number from embl.
 Function:
 Example :
 Returns : 
 Args    :


=cut

sub id {
    # HACK by th, for ensembl100:
    # change to get/set to allow id to be changed (see above)
    my ($self,$value) = @_;
    if($value){
	$self->{'_id'}=$value;
    }
    return $self->{'_id'};
}



=head2 id

 Title   : id
 Usage   : this is the primary id for ensembl. General the accession number from embl.
 Function:
 Example :
 Returns : 
 Args    :


=cut

sub embl_id {

   my ($self) = @_;
   my $id=$self->_get_Seq->id;  
   return $id;
}



=head2 get_all_Genes

 Title   : get_all_Genes
 Usage   :
 Function:
 Example :
 Returns : 
 Args    :


=cut



sub get_all_Genes {
    my ($self)=@_;
    my ($contig) = $self->get_all_Contigs;
    return $contig->get_all_Genes;
}




sub _get_Seq {

    my ($self,$value) = @_;
    if (defined $value){$self->{'annseq'}=$value;}
    return $self->{'annseq'};       
}





=head2 sv

 Title   : sv
 Function: returns the version number (not the acc.version, just verision).
 Example :
 Returns : 
 Args    :


=cut

sub sv {
   my ($self,@args) = @_;

   my $sv=1;
   $self->warn("Base class has not implemented this yet!");
   return $sv;

}


=head2 embl_version

 Title   : embl_version
 Usage   : $clone->embl_version()
 Function: Gives the value of the EMBL version, i.e. the data version
 Example : $clone->embl_version()
 Returns : version number
 Args    : none


=cut

sub embl_version {
    my ($self,@args) = @_;

my $version=1;   
# $self->warn("Base class has not implemented embl_version yet!");
    return $version;
}


=head2 seq_date

 Title   : seq_date
 Usage   : $clone->seq_date()
 Function: loops over all $contig->seq_date, throws a warning if they are different and 
           returns the first unix time value of the dna created datetime field, which indicates
           the original time of the dna sequence data
 Example : $clone->seq_date()
 Returns : unix time
 Args    : none


=cut

sub seq_date {
    my ($self,@args) = @_;

    my $date='555';
    return $date;

   
}


=head2 version

 Title   : version
 Function: Schema translation
 Example :
 Returns : 
 Args    :


=cut

sub version {
   my ($self,@args) = @_;

   #$self->warn("Called version without implementation. Probably an old object. Called sv instead");
   #return $self->sv();

   my $version='fff';
   return $version;

}


=head2 htg_phase

 Title   : htg_phase
 Usage   : this is the phase being 1,2,3,4 (4 being finished).
 Function:
 Example :
 Returns : 
 Args    :


=cut

sub htg_phase {
   my ($self,@args) = @_;

   my $phase=1;
   #$self->warn("Base class has not implemented htg_phase yet!");
   return $phase;
}


=head2 created

 Title   : created
 Usage   : $clone->created()
 Function: Gives the unix time value of the created datetime field, which indicates
           the first time this clone was put in ensembl
 Example : $clone->created()
 Returns : unix time
 Args    : none


=cut

sub created {
    my ($self,@args) = @_;
    my $created='777';
    #$self->warn("Base class has not implemented created  yet!");

    return $created;

}


=head2 modified

 Title   : modified
 Usage   : $clone->modified()
 Function: Gives the unix time value of the modified datetime field, which indicates
           the last time this clone was modified in ensembl
 Example : $clone->modified()
 Returns : unix time
 Args    : none


=cut

sub modified{
    my ($self,@args) = @_;

    my $modified ='44';

    #$self->warn("Base class has not implemented modified yet!");
    return $modified;
}


=head2 get_Contig

 Title   : get_Contig
 Usage   :
 Function:
 Example :
 Returns : 
 Args    :


=cut

sub get_Contig {
   my ($self,$value) = @_;

   my $contig;
   my $seen;
   
   if (defined $value){      
       my @contigs=$self->get_all_Contigs;
       foreach my $contig(@contigs){
	   if ($value eq $contig->id){$seen=1;}
	   else {$seen=0;}}}
   if ($seen==1){
       return $contig;

   }   
   else{$self->throw("can't get a clone without valid id");}
   
   return $contig;
   

}


=head2 get_all_Contigs

 Title   : get_all_Contigs
 Usage   : 
 Function: gets all the contigs in this clone
 Example :
 Returns : 
 Args    :


=cut

sub get_all_Contigs {
    my ($self) = @_;
    my @contigs;
    
    # HACK by th, for ensembl100:
    # pass in memory id to contig so it is set correctly there from clone
    # and not from annseq
    my $contig = Bio::EnsEMBL::EMBLLOAD::Contig->new($self->_get_Seq,$self->id);
    push @contigs,$contig;
    
    return @contigs;

}

=head2 get_all_ContigOverlaps

 Title   : get_all_ContigOverlaps
 Usage   : $obj->get_all_ContigOverlaps($newval)
 Function: 
 Example : 
 Returns : value of get_all_ContigOverlaps
 Args    : newvalue (optional)


=cut

sub get_all_ContigOverlaps{
   my ($obj,$value) = @_;

   return ();
}


1;








