#!/bin/bash
# EM Feb 14
#
# Requires erw-bash-commons to have been activated
# This script must be sourced from the directory where it is located
#

addToEnvVar "$(pwd)/bin" PATH :
#addToEnvVar "$(pwd)/lib" PERL5LIB :
#erw-pm activate perl-libraries
erw-pm activate CLGTextTools
