package CLGAuthorshipAnalytics::Verification::VerifStrategy;


#twdoc
#
# Parent class for an authorship verification strategy.
#
# Once initialized, the object can be used to compute the strategy features in the ``compute`` method for a pair of sets of probe documents; can be called as many times as required with different pairs of sets of probe docs.
#
# ---
# EM Oct 2015
# 
#/twdoc


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


#twdoc new($class, $params, $subclass)
#
# * $params:
# ** logging
# * subclass: used only to initialize the logger object with the right package id
#/twdoc
#
sub new {
    my ($class, $params, $subclass) = @_;
    my $self;
    $self->{logger} = Log::Log4perl->get_logger(defined($subclass)?$subclass:__PACKAGE__) if ($params->{logging});
#    bless($self, $class);
    return $self;
}


#twdoc compute($self, $probeDocsList)
#
# * $probeDocsLists: [ [docA1, docA2, ...] ,  [docB1, docB2,...] ]
# ** where docX = ~DocProvider
# * output: array of features values
#
#/twdoc
#
sub compute {
    my $self = shift;
    my $probeDocsLists = shift;

    confessLog($self->{logger}, "bug: calling an abstract method");
}


#twdoc featuresHeader($self)
#
# * output: array containing the names of the features
#
#/twdoc
#
sub featuresHeader {
    my $self = shift;
    confessLog($self->{logger}, "bug: calling an abstract method");
}


#twdoc newVerifStrategyFromId($strategyId, $params, ?$removeStrategyIdPrefix)
#
# static 'new' method which instantiates one of the non-abstract strategy classes. 
# The class is specified by a string id.
#
#/twdoc
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
