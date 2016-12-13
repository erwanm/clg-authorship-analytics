#!/bin/bash

if [ $# -eq 1 ]; then
    logOpt="-l $1"
    echo "$0 info: logging level = $1" 1>&2
else
    echo "$0 info: no logging" 1>&2
fi
eval "verif-author.pl $logOpt -H -c -v 'stopwords50:tests/data/stop-words/english/50.list;stopwords200:tests/data/stop-words/english/200.list' tests/001-all-obs-types.conf tests/data/english-20-cases/EN001/known01.txt tests/data/english-20-cases/EN001/unknown.txt"
#echo "$0 info: showing count files" 1>&2
#ls -l tests/data/english-20-cases/EN001/ 1>&2
echo "$0 info: removing count files" 1>&2
rm -f tests/data/english-20-cases/EN001/*count*
