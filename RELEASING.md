# Release process

`VERSION` records the standalone Docker manager version using semantic
versioning. Its major and minor numbers are not required to match the source
installer version.

## Release checklist

1. Refresh image and component versions in .env.example, compose.yaml and the
   relevant Dockerfiles. Recheck upstream PHP support, MySQL LTS tracks,
   Temurin LTS availability, APISIX/etcd releases and optional application
   release notes.
2. Update VERSION and release notes.
3. Run ./tests/static.sh.
4. Run ./tests/runtime.sh on Docker-enabled Linux.
5. Push only after CI passes, then tag the value from VERSION with a v prefix.
