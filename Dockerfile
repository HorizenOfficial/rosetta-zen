# Copyright 2020 Coinbase, Inc.
# Copyright 2020 Zen Blockchain Foundation
# Copyright 2023 Horizen Foundation
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

## Build zend
FROM ubuntu:20.04 as zend-builder

MAINTAINER cronic@horizen.io

SHELL ["/bin/bash", "-c"]

# Latest release zen 5.0.7
ARG ZEN_COMMITTISH=v5.0.7
ARG IS_RELEASE=false
# cronic <cronic@zensystem.io> https://keys.openpgp.org/vks/v1/by-fingerprint/219F55740BBF7A1CE368BA45FB7053CE4991B669
# Luigi Varriale <luigi@horizenlabs.io> https://keys.openpgp.org/vks/v1/by-fingerprint/FC3388A460ACFAB04E8328C07BB2A1D2CFDFCD2C
# Daniele Rogora <danielerogora@horizenlabs.io> https://keys.openpgp.org/vks/v1/by-fingerprint/1754AAB85B4A25165464478F670FC45BE6CA359F
ARG ZEND_MAINTAINER_KEYS="219f55740bbf7a1ce368ba45fb7053ce4991b669 FC3388A460ACFAB04E8328C07BB2A1D2CFDFCD2C 1754AAB85B4A25165464478F670FC45BE6CA359F"

RUN set -euxo pipefail \
    && export DEBIAN_FRONTEND=noninteractive \
    && apt-get update \
    && apt-get -y --no-install-recommends install apt-utils \
    && apt-get -y --no-install-recommends dist-upgrade \
    && apt-get -y --no-install-recommends install autoconf automake \
      bsdmainutils build-essential ca-certificates cmake curl dirmngr fakeroot \
      git g++-multilib gnupg2 libc6-dev libgomp1 libtool m4 ncurses-dev \
      pkg-config python3 zlib1g-dev \
    && git clone https://github.com/HorizenOfficial/zen.git \
    && cd /zen && git checkout "${ZEN_COMMITTISH}" \
    && if [ "$IS_RELEASE" = "true" ]; then \
      read -a keys <<< "$ZEND_MAINTAINER_KEYS" \
      && for key in "${keys[@]}"; do \
        gpg2 --batch --keyserver keyserver.ubuntu.com --keyserver-options timeout=15 --recv "$key" || \
        gpg2 --batch --keyserver hkps://keys.openpgp.org --keyserver-options timeout=15 --recv "$key" || \
        gpg2 --batch --keyserver hkp://p80.pool.sks-keyservers.net:80 --keyserver-options timeout=15 --recv-keys "$key" || \
        gpg2 --batch --keyserver hkp://ipv4.pool.sks-keyservers.net --keyserver-options timeout=15 --recv-keys "$key" || \
        gpg2 --batch --keyserver hkp://pgp.mit.edu:80 --keyserver-options timeout=15 --recv-keys "$key"; \
      done \
      && if git verify-tag -v "${ZEN_COMMITTISH}"; then \
        echo "Valid signed tag"; \
      else \
        echo "Not a valid signed tag"; \
        exit 1; \
      fi \
      && ( gpgconf --kill dirmngr || true ) \
      && ( gpgconf --kill gpg-agent || true ); \
    fi \
    && export MAKEFLAGS="-j $(($(nproc)+1))" && ./zcutil/build.sh $MAKEFLAGS


## Build Rosetta Server Components
FROM ubuntu:20.04 as rosetta-builder

MAINTAINER cronic@horizen.io

SHELL ["/bin/bash", "-c"]

ARG GOLANG_VERSION=1.17.2
ARG GOLANG_DOWNLOAD_SHA256=f242a9db6a0ad1846de7b6d94d507915d14062660616a61ef7c808a76e4f1676
ARG GOLANG_DOWNLOAD_URL="https://golang.org/dl/go${GOLANG_VERSION}.linux-amd64.tar.gz"

COPY . /go/src

RUN set -euxo pipefail \
    && export DEBIAN_FRONTEND=noninteractive \
    && apt-get update \
    && apt-get -y --no-install-recommends install apt-utils \
    && apt-get -y --no-install-recommends dist-upgrade \
    && apt-get -y --no-install-recommends install ca-certificates curl g++ gcc git make \
    && curl -fsSL "$GOLANG_DOWNLOAD_URL" -o /tmp/golang.tar.gz \
    && echo "${GOLANG_DOWNLOAD_SHA256}  /tmp/golang.tar.gz" | sha256sum -c - \
    && tar -C /usr/local -xzf /tmp/golang.tar.gz \
    && export GOPATH="/go" && export PATH="${GOPATH}/bin:/usr/local/go/bin:${PATH}" \
    && mkdir "${GOPATH}/bin" && chmod -R 777 "${GOPATH}" \
    && cd "${GOPATH}/src" && go build


## Build Final Image
FROM ubuntu:20.04

MAINTAINER cronic@horizen.io

SHELL ["/bin/bash", "-c"]

WORKDIR /app

# Copy zend and fetch-params.sh
COPY --from=zend-builder /zen/src/zend /zen/zcutil/fetch-params.sh /app/

# Copy rosetta-zen and assets
COPY --from=rosetta-builder /go/src/rosetta-zen /go/src/assets/* /app/

# Copy entrypoint script
COPY entrypoint.sh /app/

# Install runtime dependencies and set up home folder for nobody user.
# As it's best practice to not run as root even inside a container,
# we run as nobody and change the home folder to "/data".
RUN set -euxo pipefail \
    && export DEBIAN_FRONTEND=noninteractive \
    && apt-get update \
    && apt-get -y --no-install-recommends install apt-utils \
    && apt-get -y --no-install-recommends dist-upgrade \
    && apt-get -y --no-install-recommends install ca-certificates curl libgomp1 \
    && apt-get -y clean && apt-get -y autoclean \
    && rm -rf /var/{lib/apt/lists/*,cache/apt/archives/*.deb,tmp/*,log/*} /tmp/* \
    && mkdir -p /data \
    && for path in /data /app; do chown -R nobody:nogroup $path && chmod 2755 $path; done \
    && for file in /app/{entrypoint.sh,rosetta-zen,fetch-params.sh,zend}; do chmod 755 $file; done \
    && sed -i 's|nobody:/nonexistent|nobody:/data|' /etc/passwd

VOLUME ["/data"]

USER nobody

ENTRYPOINT ["/app/entrypoint.sh"]

CMD ["/app/rosetta-zen"]
