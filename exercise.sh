#!/usr/bin/env bash

# **exercise.sh** - using the cloud can be fun

# we will use the ``nova`` cli tool provided by the ``python-novaclient``
# package
#


# This script exits on an error so that errors don't compound and you see
# only the first error that occured.
set -o errexit

# Print the commands being run so that we can see the command that triggers
# an error.  It is also useful for following allowing as the install occurs.
set -o xtrace


# Settings
# ========

# Use openrc + stackrc + localrc for settings
source ./openrc

# Get a token for clients that don't support service catalog
# ==========================================================

# manually create a token by querying keystone (sending JSON data).  Keystone
# returns a token and catalog of endpoints.  We use python to parse the token
# and save it.

TOKEN=`curl -s -d  "{\"passwordCredentials\": {\"username\": \"$NOVA_USERNAME\", \"password\": \"$NOVA_API_KEY\"}, \"tenantid\": \"$NOVA_PROJECT_ID\"}" -H "Content-type: application/json" http://$HOST_IP:5000/v2.0/tokens | python -c "import sys; import json; tok = json.loads(sys.stdin.read()); print tok['auth']['token']['id'];"`

# Launching a server
# ==================

# List servers for tenant:
nova list

# Images
# ------

# Nova has a **deprecated** way of listing images.
nova image-list

# But we recommend using glance directly
glance -A $TOKEN index

# Let's grab the id of the first AMI image to launch
IMAGE=`glance -A $TOKEN index | egrep ami | cut -d" " -f1`

# determine flavor
# ----------------

# List of flavors:
nova flavor-list

# and grab the first flavor in the list to launch
FLAVOR=`nova flavor-list | head -n 4 | tail -n 1 | cut -d"|" -f2`

NAME="myserver"

nova boot --flavor $FLAVOR --image $IMAGE $NAME # --security_groups=$SECGROUP

# Testing
# =======

# First check if it spins up (becomes active and responds to ping on
# internal ip).  If you run this script from a nova node, you should
# bypass security groups and have direct access to the server.

# Waiting for boot
# ----------------

# check that the status is active within 10 seconds
if ! timeout 10 sh -c "while ! nova show $NAME | grep status | grep -q ACTIVE; do sleep 1; done"; then
    echo "server didn't become active!"
    exit 1
fi

# get the IP of the server
IP=`nova show $NAME | grep "private network" | cut -d"|" -f3`

# for single node deployments, we can ping private ips
# MULTI_HOST=${MULTI_HOST:-0}
if [ "$MULTI_HOST" = "0" ]; then
    # sometimes the first ping fails (10 seconds isn't enough time for the VM's
    # network to respond?), so let's ping for 15 seconds with a timeout
    # of a second.
    if ! timeout 15 sh -c "while ! ping -c1 -w1 $IP; do sleep 1; done"; then
        echo "Couldn't ping server"
        exit 1
    fi
fi

# shutdown the server
nova delete $NAME

# FIXME: validate shutdown within 5 seconds
# (nova show $NAME returns 1 or status != ACTIVE)?

# Testing Euca2ools
# ==================

# make sure that we can describe instances
# euca-describe-instances
