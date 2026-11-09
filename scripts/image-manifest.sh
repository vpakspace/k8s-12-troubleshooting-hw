#!/usr/bin/env bash
# image-manifest.sh <repo> <tag> — какой формат манифеста реестр Docker Hub отдаёт для образа.
# Нужен, чтобы независимо от кластера проверить версию схемы манифеста (schema 1 containerd 2.x не поддерживает).
set -euo pipefail
repo=$1; tag=$2
accept='application/vnd.oci.image.index.v1+json, application/vnd.oci.image.manifest.v1+json, application/vnd.docker.distribution.manifest.v2+json, application/vnd.docker.distribution.manifest.list.v2+json'
tok=$(curl -s "https://auth.docker.io/token?service=registry.docker.io&scope=repository:${repo}:pull" \
      | python3 -I -c 'import sys,json; print(json.load(sys.stdin)["token"])')
tmp=$(mktemp)
ct=$(curl -s -o "$tmp" -w '%{content_type}' -H "Authorization: Bearer $tok" -H "Accept: $accept" \
      "https://registry-1.docker.io/v2/${repo}/manifests/${tag}")
sv=$(python3 -I -c 'import sys,json; print(json.load(open(sys.argv[1])).get("schemaVersion"))' "$tmp")
rm -f "$tmp"
printf '%s:%s\n  Content-Type:  %s\n  schemaVersion: %s\n' "$repo" "$tag" "$ct" "$sv"
