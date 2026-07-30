# Repository Guidance

## Scope

This repository owns the standalone OneinStack Docker Compose deployment.
Do not add host package installation, SSH, firewall or reboot management here;
those belong to the source installer or the deployment platform.

## Supported versions

Offer production choices based on current upstream support, not historical
installer parity. Check php.net before changing PHP branches, accept only MySQL
LTS tracks, and offer Eclipse Temurin LTS lines while Adoptium still publishes
updates for them. Default to the latest Temurin LTS and do not add JDK builds
without a maintained upstream image source. Refresh APISIX and its etcd state
store from their official maintained container sources.

## Verification

Run ./tests/static.sh after every change. For release or lifecycle changes,
also run ./tests/runtime.sh on Docker-enabled Linux. Never describe static
checks as container build or runtime acceptance.
