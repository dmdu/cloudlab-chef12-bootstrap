#!/bin/bash

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <path to the manifest file>"
    exit 1
fi

# Foreign manifest - manifest for another experiment
FM=$1

if [ ! -r $FM ]; then
    echo "Cannot read the specified manifest file"
    exit 1
fi

HOSTNAMES_LONG=`cat $FM | \
                xmlstarlet fo | \
                xmlstarlet sel -B -t -c "//_:node" | \
                sed -r 's/<node/\n<node/g' | \
                sed -r "s/.*host\ name=\"([^\"]*)\".*/\1/"`

for HOST in $HOSTNAMES_LONG; do
   HOSTNAME_SHORT=`echo $HOST| sed -s "s/\..*//"`
   # echo "$HOST, $HOSTNAME_SHORT"

   if [[ $HOST == *"clemson"* ]]; then SITE="clemson" ; fi
   if [[ $HOST == *"utah"* ]];    then SITE="utah" ; fi
   if [[ $HOST == *"wisc"* ]];    then SITE="wisconsin" ; fi

   knife bootstrap $HOST -N $HOSTNAME_SHORT -E $SITE
   echo "$HOSTNAME_SHORT $HOST" >> /etc/hosts
done

# Tests
knife status -r
knife ssh "name:*" uptime
