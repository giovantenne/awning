#!/bin/bash

if [ ! -f /data/.lnd/password.txt ]; then
  echo $LND_PASSWORD > /data/.lnd/password.txt
fi
lnd --tor.targetipaddress=`hostname -i`

