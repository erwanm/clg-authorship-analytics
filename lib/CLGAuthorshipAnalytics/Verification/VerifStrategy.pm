package CLGAuthorshipAnalytics::Verification::VerifStrategy;

# EM Oct 2015
# 
#


use strict;
use warnings;
use Carp;
use Log::Log4perl;
use CLGTextTools::Commons qw//;

use base 'Exporter';
our @EXPORT_OK = qw//;



#
# $params:
# * logging
#
sub new {
    my ($class, $params) = @_;
    my $self;
    $self->{logger} = Log::Log4perl->get_logger(__PACKAGE__) if ($params->{logging});
    bless($self, $class);
    return $self;
}



#
# * $probeDocsLists: [ [docA1, docA2, ...] ,  [docB1, docB2,...] ]
#    ** where docX = hash: docX->{obsType}->{ngram} = freq
# * output: array of features values
sub compute {
    my $self = shift;
    my $probeDocsLists = shift;

    confessLog($self->{logger}, "bug: calling an abstract method");
}





1;
