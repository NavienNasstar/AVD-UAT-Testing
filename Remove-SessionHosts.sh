#!/bin/bash
# Deletes ONLY Virtual Machines, Network Interfaces, and OS Disks in the given
# resource group. No other resource type (vnet, keyvault, storage, etc.) is touched.
#
# Usage:
#   ./Remove-SessionHosts.sh <resourceGroupName> <namingSuffix>
#
#   <resourceGroupName>  RG containing the VMs.
#   <namingSuffix>       Shared part of the names, e.g. nas-uks-avd-general-prod
#                        Resources matched:
#                          VM   : vm-<namingSuffix>*
#                          NIC  : nic-<namingSuffix>*
#                          Disk : osdisk-<namingSuffix>*  (and must be an OS disk)
#
# OS disks are also checked via the 'osType' property, which only exists on
# OS disks, so data disks are never touched.

set -euo pipefail

RG="${1:?Resource group name is required}"
SUFFIX="${2:?Naming suffix is required, e.g. nas-uks-avd-general-prod}"

echo "Target resource group : $RG"
echo "Naming suffix         : $SUFFIX"

VM_QUERY="[?starts_with(name, 'vm-${SUFFIX}')].id"
NIC_QUERY="[?starts_with(name, 'nic-${SUFFIX}')].id"
DISK_QUERY="[?osType!=null && starts_with(name, 'osdisk-${SUFFIX}')].id"

echo ""
echo "=== Deleting Virtual Machines ==="
az vm list -g "$RG" --query "$VM_QUERY" -o tsv | while IFS=$'\t' read -r id; do
  [ -z "$id" ] && continue
  echo "Deleting VM: $id"
  az vm delete --ids "$id" --yes
done

echo ""
echo "=== Deleting Network Interfaces ==="
az network nic list -g "$RG" --query "$NIC_QUERY" -o tsv | while IFS=$'\t' read -r id; do
  [ -z "$id" ] && continue
  echo "Deleting NIC: $id"
  az network nic delete --ids "$id"
done

echo ""
echo "=== Deleting OS Disks ==="
az disk list -g "$RG" --query "$DISK_QUERY" -o tsv | while IFS=$'\t' read -r id; do
  [ -z "$id" ] && continue
  echo "Deleting OS Disk: $id"
  az disk delete --ids "$id" --yes
done

echo ""
echo "Cleanup complete."
