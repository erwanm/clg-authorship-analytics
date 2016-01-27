package CLGAuthorshipAnalytics::Verification::Basic;

# EM December 2015
# 
#


use strict;
use warnings;
use Carp;
use Log::Log4perl;
use CLGTextTools::Stats qw/pickInList pickNSloppy aggregateVector/;
use CLGTextTools::Commons qw/assignDefaultAndWarnIfUndef/;
use CLGAuthorshipAnalytics::Verification::VerifStrategy;
use CLGTextTools::Logging qw/confessLog cluckLog/;
use CLGTextTools::SimMeasures::MinMax;

our @ISA=qw/CLGAuthorshipAnalytics::Verification::VerifStrategy/;

use base 'Exporter';
our @EXPORT_OK = qw//;






#
# $params:
# * logging
# * obsTypesList 
# * simMeasure:  a CLGTextTools::Measure object (initialized) (default minMax)
# * multipleProbeAggregate: random,  median, arithm, geom, harmo. If there are more than one probe doc on either side (or both), specifies which method should be used to aggregate the similarity scores. If "random" (default), then a default doc is picked among the list (disadvantage: same input can give different results). Otherwise the similarity is computed between all pairs (cartesian product NxM), and the values are aggregated according to the parameter (disadvantage: NxM longer).
#
sub new {
    my ($class, $params) = @_;
    my $self = $class->SUPER::new($params,__PACKAGE__);
    $self->{obsTypesList} = $params->{obsTypesList};

    my $defaultSim= CLGTextTools::SimMeasures::MinMax->new($params); # if (!defined($params->{simMeasure}));
    $self->{simMeasure} = assignDefaultAndWarnIfUndef("simMeasure", $params->{simMeasure}, $defaultSim, $self->{logger}) ;
    $self->{multipleProbeAggregate} =  assignDefaultAndWarnIfUndef("multipleProbeAggregate", $params->{multipleProbeAggregate}, "random", $self->{logger}) ;
    bless($self, $class);
    return $self;
}




#
# * $probeDocsLists: [ [docA1, docA2, ...] ,  [docB1, docB2,...] ]
#    ** where docX = DocProvider
#
sub compute {
    my $self = shift;
    my $probeDocsLists = shift;

    my @features;
    $self->{logger}->debug("Basic strategy: computing features between pair of sets of docs") if ($self->{logger});
    confessLog($self->{logger}, "Cannot process case: no obs types at all") if ((scalar(@{$self->{obsTypesList}})==0) && $self->{logger});
    foreach my $obsType (@{$self->{obsTypesList}}) {
	my $simValue;
	if ($self->{multipleProbeAggregate} eq "random") {
	    my @probeDocPair = map { pickInList($_) } @$probeDocsLists;
	    $simValue = $self->{simMeasure}->compute($probeDocPair[0]->getObservations($obsType), $probeDocPair[1]->getObservations($obsType));
	} else {
	    my @values;
	    foreach my $doc1 (@{$probeDocsLists->[0]}) {
		foreach my $doc2 (@{$probeDocsLists->[1]}) {
		    my $res = $self->{simMeasure}->compute($doc1->getObservations($obsType), $doc2->getObservations($obsType));
		    push(@values, $res);
		}
	    }
	    $simValue = aggregateVector(\@values, $self->{multipleProbeAggregate});
	}
	push(@features, $simValue);
    }

    return \@features;
}




1;
