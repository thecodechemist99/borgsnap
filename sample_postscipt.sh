#!/bin/bash

#
# If this script is called by borgsnap it will run for all datasets configured.
#
# The dataset is passed to this script as variable $1 - if you only want to run
# this script on a specific dataset, use an if statement to check as below:
#

if [[ "$1" = "pool/dataset1" ]]; then
  echo do stuff!
  sleep 10
fi
