#!/bin/bash
#
# Remove leftover cloud resources created by a Milpa controller.
#

function usage() {
    {
        echo "Usage $0 <milpa-nametag>"
        echo "You can also set the environment variables MILPA_NAMETAG."
    } >&2
    exit 1
}

function check_prg() {
    $1 --version || {
        {
            echo "Can't find $prg."
        } >&2
        exit 2
    }
}

if [[ "$1" != "" ]]; then
    MILPA_NAMETAG="$1"
fi
if [[ -z "$MILPA_NAMETAG" ]]; then
    usage
fi
shift

if [[ -n "$1" ]]; then
    usage
fi

check_prg az
check_prg jq

az vm list | jq -r ".[] | select (.tags[\"MilpaNametag\"]) | select(.tags[\"MilpaNametag\"]==\"$MILPA_NAMETAG\") | .resourceGroup" | sort | uniq | xargs -n1 -P20 --no-run-if-empty az group delete --yes --name

exit 0
