#!/bin/bash

lnd --tor.targetipaddress=`hostname -i` --alias=$NODE_ALIAS

