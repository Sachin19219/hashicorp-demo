#!/usr/bin/env bash
set -e

echo "Started: $(date)"
echo "Generating AMI..."
export AAKI=$(sed "2q;d" ~/.aws/credentials | awk -F'=' '{print $2}' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
export ASAK=$(sed "3q;d" ~/.aws/credentials | awk -F'=' '{print $2}' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
export AMI_ID=$(packer build -var aws_access_key=${AAKI} -var aws_secret_key=${ASAK} -machine-readable basebuild.json | awk -F, '$0 ~/artifact,0,id/ {print $6}' | cut -f2 -d:)

echo "Generating AMI Complete"
echo "Finished: $(date)"