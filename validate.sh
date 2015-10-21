#!/bin/bash

# This is the script to run locally, before checkin.
# It's also the script used by Jenkins CI.

set -xe

which -a stack

TOP=`pwd`

cd $TOP/acc_hs/
./validate.sh

cd $TOP/acc_rkt/
./validate.sh