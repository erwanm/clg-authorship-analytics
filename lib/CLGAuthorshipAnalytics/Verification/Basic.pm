package CLGAuthorshipAnalytics::Verification::Basic;

# EM December 2015
# 
#


use strict;
use warnings;
use Carp;
use Log::Log4perl;
use CLGTextTools::Stats qw/pickInList pickNSloppy aggregateVector/;
use CLGTextTools::Commons qw//;
use CLGAuthorshipAnalytics::Verification::VerifStrategy;
use CLGTextTools::Logging qw/confessLog cluckLog/;

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
    $self->{simMeasure} = assignDefaultAndWarnIfUndef("simMeasure", $params->{simMeasure}, CLGTextTools::SimMeasures::MinMax->new(), $self->{logger}) ;
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
    foreach my $obsType (@{$self->{obsTypesList}}) {
	my $simValue;
	if ($self->{multipleProbeAggregate} eq "random") {
	    my @probeDocPair = map { pickInList($_) } @$probeDocsLists;
	    $simValue = $self->{simMeasure}->compute($probeDocPair[0]->{$obsType}, $probeDocPair[1]->{$obsType});
	} else {
	    my @values;
	    foreach my $doc1 (@{$probeDocsLists->[0]}) {
		foreach my $doc2 (@{$probeDocsLists->[1]}) {
		    my $res = $self->{simMeasure}->compute($doc1->{$obsType}, $doc2->{$obsType});
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
