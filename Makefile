.PHONY: deps build run lint mocks run-mainnet-online run-mainnet-offline run-testnet-online \
	run-testnet-offline check-comments add-license check-license shorten-lines test \
	coverage spellcheck salus build-local coverage-local format check-format

ADDLICENSE_CMD=go run github.com/google/addlicense
ADDLICENCE_SCRIPT=${ADDLICENSE_CMD} -c "Coinbase, Inc." -l "apache" -v
SPELLCHECK_CMD=go run github.com/client9/misspell/cmd/misspell
GOLINES_CMD=go run github.com/segmentio/golines
GOLINT_CMD=go run golang.org/x/lint/golint
GOVERALLS_CMD=go run github.com/mattn/goveralls
GOIMPORTS_CMD=go run golang.org/x/tools/cmd/goimports
GO_PACKAGES=./services/... ./indexer/... ./zen/... ./zend/... ./zenutil/... ./configuration/...
GO_FOLDERS=$(shell echo ${GO_PACKAGES} | sed -e "s/\.\///g" | sed -e "s/\/\.\.\.//g")
TEST_SCRIPT=go test ${GO_PACKAGES}
LINT_SETTINGS=golint,misspell,gocyclo,gocritic,whitespace,goconst,gocognit,bodyclose,unconvert,lll,unparam
PWD=$(shell pwd)
GZIP_CMD=$(shell command -v pigz || echo gzip)
NOFILE=100000
# cronic <cronic@zensystem.io> https://keys.openpgp.org/vks/v1/by-fingerprint/219F55740BBF7A1CE368BA45FB7053CE4991B669
# Luigi Varriale <luigi@horizenlabs.io> https://keys.openpgp.org/vks/v1/by-fingerprint/FC3388A460ACFAB04E8328C07BB2A1D2CFDFCD2C
# Paolo Tagliaferri <paolotagliaferri@horizenlabs.io> https://keys.openpgp.org/vks/v1/by-fingerprint/D0459BD6AAD14E8D9C83FF1E8EDE560493C65AC1
# Daniele Rogora <danielerogora@horizenlabs.io> https://keys.openpgp.org/vks/v1/by-fingerprint/661F6FC64773A0F47936625FD3A22623FF9B9F11
# Alessandro Petrini <apetrini@horizenlabs.io> https://keys.openpgp.org/vks/v1/by-fingerprint/BF1FCDC8AEE7AE53013FF0941FCA7260796CB902
ZEND_MAINTAINER_KEYS?=219f55740bbf7a1ce368ba45fb7053ce4991b669 FC3388A460ACFAB04E8328C07BB2A1D2CFDFCD2C 1754AAB85B4A25165464478F670FC45BE6CA359F
ZEN_COMMITTISH?=v5.0.6
DOCKER_IMAGE_NAME?=zencash/rosetta-zen

deps:
	go get ./...

build:
	docker build --pull -t rosetta-zen:latest https://github.com/HorizenOfficial/rosetta-zen

build-local:
	docker build --pull --build-arg ZEN_COMMITTISH=${ZEN_COMMITTISH} -t rosetta-zen:latest .

build-release:
	# make sure to always set version with vX.X.X
	docker build --pull --no-cache --build-arg IS_RELEASE=true --build-arg ZEND_MAINTAINER_KEYS="${ZEND_MAINTAINER_KEYS}" --build-arg ZEN_COMMITTISH=${ZEN_COMMITTISH} -t rosetta-zen:$(version) .;
	docker save rosetta-zen:$(version) | ${GZIP_CMD} > rosetta-zen-$(version).tar.gz;
	@echo $(DOCKER_WRITER_PASSWORD) | docker login -u $(DOCKER_WRITER_USERNAME) --password-stdin;
	docker tag rosetta-zen:$(version) ${DOCKER_IMAGE_NAME}:latest
	docker push ${DOCKER_IMAGE_NAME}:latest;
	docker tag rosetta-zen:$(version) ${DOCKER_IMAGE_NAME}:$(version)
	docker push ${DOCKER_IMAGE_NAME}:$(version);

run-mainnet-online:
	docker container rm rosetta-zen-mainnet-online || true
	docker run --rm -v "${PWD}/zen-data:/data" ubuntu:18.04 bash -c 'chown -R nobody:nogroup /data';
	docker run -d --name=rosetta-zen-mainnet-online --ulimit "nofile=${NOFILE}:${NOFILE}" -v "${PWD}/zen-data:/data" -e "MODE=ONLINE" -e "NETWORK=MAINNET" -e "PORT=8080" -p 8080:8080 -p 9033:9033 rosetta-zen:latest;

run-mainnet-offline:
	docker container rm rosetta-zen-mainnet-offline || true
	docker run -d --name=rosetta-zen-mainnet-offline -e "MODE=OFFLINE" -e "NETWORK=MAINNET" -e "PORT=8081" -p 8081:8081 rosetta-zen:latest

run-testnet-online:
	docker container rm rosetta-zen-testnet-online || true
	docker run --rm -v "${PWD}/zen-data-testnet:/data" ubuntu:18.04 bash -c 'chown -R nobody:nogroup /data';
	docker run -d --name=rosetta-zen-testnet-online --ulimit "nofile=${NOFILE}:${NOFILE}" -v "${PWD}/zen-data-testnet:/data" -e "MODE=ONLINE" -e "NETWORK=TESTNET" -e "PORT=8080" -p 8080:8080 -p 19033:19033 rosetta-zen:latest;

run-testnet-offline:
	docker container rm rosetta-zen-testnet-offline || true
	docker run -d --name=rosetta-zen-testnet-offline -e "MODE=OFFLINE" -e "NETWORK=TESTNET" -e "PORT=8081" -p 8081:8081 rosetta-zen:latest

train:
	./zstd-train.sh $(network) transaction $(data-directory)

check-comments:
	${GOLINT_CMD} -set_exit_status ${GO_FOLDERS} .

lint: | check-comments
	golangci-lint run --timeout 2m0s -v -E ${LINT_SETTINGS},gomnd

add-license:
	${ADDLICENCE_SCRIPT} .

check-license:
	${ADDLICENCE_SCRIPT} -check .

shorten-lines:
	${GOLINES_CMD} -w --shorten-comments ${GO_FOLDERS} .

format:
	gofmt -s -w -l .
	${GOIMPORTS_CMD} -w .

check-format:
	! gofmt -s -l . | read
	! ${GOIMPORTS_CMD} -l . | read

test:
	${TEST_SCRIPT}

coverage:
	if [ "${COVERALLS_TOKEN}" ]; then ${TEST_SCRIPT} -coverprofile=c.out -covermode=count; ${GOVERALLS_CMD} -coverprofile=c.out -repotoken ${COVERALLS_TOKEN}; fi

coverage-local:
	${TEST_SCRIPT} -cover

salus:
	docker run --rm -t -v ${PWD}:/home/repo coinbase/salus

spellcheck:
	${SPELLCHECK_CMD} -error .

mocks:
	rm -rf mocks;
	mockery --dir indexer --all --case underscore --outpkg indexer --output mocks/indexer;
	mockery --dir services --all --case underscore --outpkg services --output mocks/services;
	${ADDLICENCE_SCRIPT} .;
