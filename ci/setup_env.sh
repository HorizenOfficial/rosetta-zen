#!/bin/bash

set -eo pipefail

if [ ! -z "${TRAVIS_TAG}" ]; then
  export GNUPGHOME="$(mktemp -d 2>/dev/null || mktemp -d -t 'GNUPGHOME')"
  echo "Tagged build, fetching maintainer keys."
    gpg -v --batch --keyserver hkp://p80.pool.sks-keyservers.net:80 --recv-keys $MAINTAINER_KEYS ||
    gpg -v --batch --keyserver hkp://ipv4.pool.sks-keyservers.net --recv-keys $MAINTAINER_KEYS ||
    gpg -v --batch --keyserver hkp://pgp.mit.edu:80 --recv-keys $MAINTAINER_KEYS
  if git verify-tag -v "${TRAVIS_TAG}"; then
    echo "Valid signed tag"
    export version="${TRAVIS_TAG}"
  fi
fi
