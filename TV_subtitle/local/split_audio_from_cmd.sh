#! /bin/bash
# Author: Judy Fong
# License: Apache 2.0
# SBATCH

while IFS="" read -r p || [ -n "$p" ]
do
  echo "$p"
  $p 2> /dev/null
done < $1
