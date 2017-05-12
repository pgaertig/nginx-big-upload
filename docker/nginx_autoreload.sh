#!/bin/bash

#This script detects when the file is touched.
#inotifywait could be used for local mounts but it doesn't support remote file systems.

#Save initial file time
b=$(stat -c%Y "$1")

echo "Waiting for touches of $1 to auroreload. Check interval is $2 seconds."

# Cheap loop
while :; do
  #Get current time of file 
  a=$(stat -c%Y "$1")

  #Compare times
  if [ "$b" != "$a" ] ; then
    b="$a"
    sleep 5 #Debounce in case some other configuration files are changed with some delay
    echo "$1 touched - reloading nginx"
    nginx -t && nginx -s reload
  fi

  sleep $2
done
