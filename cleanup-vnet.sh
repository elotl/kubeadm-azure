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

while true; do
    groups=$(az vm list | jq -r ".[] | select (.tags[\"MilpaNametag\"]) | select(.tags[\"MilpaNametag\"]==\"$MILPA_NAMETAG\") | .resourceGroup" | sort | uniq)
    if [[ -z "$groups" ]]; then
        break
    fi
    echo "Removing resource groups:"
    echo "$groups"
    for group in $groups; do
        az group delete --yes -g $group
    done
done

exit 0
