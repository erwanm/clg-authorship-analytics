package CLGAuthorshipAnalytics::Verification::VerifStrategy;

# EM Oct 2015
# 
#


use strict;
use warnings;
use Carp;
use Log::Log4perl;
use CLGTextTools::Commons qw/readParamGroupAsHashFromConfig/;
use CLGAuthorshipAnalytics::Verification::Basic;
use CLGAuthorshipAnalytics::Verification::Universum;
use CLGAuthorshipAnalytics::Verification::Impostors;

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
#    bless($self, $class);
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
 #   my $keepOtherParams = shift; # optional (used only if $removeStrategyIdPrefix is defined)

    my $res;
    my $strategyParams; 
    if ($removeStrategyIdPrefix) { 
	$strategyParams = readParamGroupAsHashFromConfig($params, $strategyId, 1); # always keep other params, don't know how to manage otherwise (especially in the case of impostors)
#	$strategyParams->{logging} = $params->{logging}; # add general parameters; TODO: others??
    } else { 
	$strategyParams = $params;
    }
    if ($strategyId eq "basic") {
	$res = CLGAuthorshipAnalytics::Verification::Basic->new($strategyParams);
    } elsif ($strategyId eq "univ") {
	$res = CLGAuthorshipAnalytics::Verification::Universum->new($strategyParams);
    } elsif ($strategyId eq "GI") {
	$res = CLGAuthorshipAnalytics::Verification::Impostors->new($strategyParams);
    } else {
	confess("Error: invalid strategy id '$strategyId', cannot instanciate VerifStrategy class.");
    }
    return $res;
}


1;
