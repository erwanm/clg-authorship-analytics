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
our @EXPORT_OK = qw/newVerifStrategyFromId/;



#
# $params:
# * logging
#
sub new {
    my ($class, $params, $subclass) = @_;
    my $self;
    $self->{logger} = Log::Log4perl->get_logger(defined($subclass)?$subclass:__PACKAGE__) if ($params->{logging});
    bless($self, $class);
    return $self;
}



#
# * $probeDocsLists: [ [docA1, docA2, ...] ,  [docB1, docB2,...] ]
#    ** where docX = DocProvider
# * output: array of features values
sub compute {
    my $self = shift;
    my $probeDocsLists = shift;

    confessLog($self->{logger}, "bug: calling an abstract method");
}


#
# static 'new' method which instantiates one of the non-abstract strategy classes. 
# The class is specified by a string id.
#
sub newVerifStrategyFromId {
    my $strategyId = shift;
    my $params = shift;
    my $removeStrategyIdPrefix = shift; # optional

    my $res;
    my $strategyParams = ($removeStrategyIdPrefix) ? readParamGroupAsHashFromConfig($params, $strategyId) : $params;
    if ($strategyId eq "basic") {
	my $res = CLGAuthorshipAnalytics::Verification::Basic->new($strategyParams);
    } elsif ($strategyId eq "univ") {
	my $res = CLGAuthorshipAnalytics::Verification::Universum->new($strategyParams);
    } elsif ($strategyId eq "GI") {
	my $res = CLGAuthorshipAnalytics::Verification::Impostors->new($strategyParams);
    } else {
	confess("Error: invalid strategy id '$strategyId', cannot instanciate VerifStrategy class.");
    }
    return $res;
}


1;
