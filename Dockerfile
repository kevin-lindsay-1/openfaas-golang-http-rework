ARG TARGETPLATFORM
ARG BUILDPLATFORM
ARG TARGETOS
ARG TARGETARCH
ARG WATCHDOG_VERSION="0.9.6"
ARG GOLANG_VERSION="1.18.3"
ARG GOLANG_ALPINE_VERSION="3.16"
ARG ALPINE_VERSION="3.16.0"

###
# STAGE
###
FROM --platform=${TARGETPLATFORM:-linux/amd64} ghcr.io/openfaas/of-watchdog:${WATCHDOG_VERSION} as watchdog

###
# STAGE
###
FROM golang:${GOLANG_VERSION}-alpine${GOLANG_ALPINE_VERSION} as go
ENV GOCACHE="/usr/root/.go-cache"
RUN apk add --upgrade --no-cache "build-base"

###
# STAGE
###
FROM go as cache
ENV GOCACHE="/usr/root/.go-cache"
RUN apk add --upgrade --no-cache "build-base"
WORKDIR "/usr/root"
# Copy module information
COPY [ "./function/go.sum", "./function/go.mod", "./" ]
COPY [ "./function/vendor/", "./vendor/" ]
# Precompile vendor binaries for caching purposes
RUN go build -v "./vendor/..."

###
# STAGE
###
FROM go as prepare
ENV GOCACHE="/usr/root/.go-cache"
WORKDIR "/usr/root/function"
COPY --from=cache [ "/usr/root/.go-cache/", "./.go-cache/" ]
COPY [ "./function/", "./" ]

###
# STAGE
###
FROM prepare as test
WORKDIR "/usr/root/function"
# Run all tests in this directory and any sub-directories
RUN go test \
    # If any tests fail, immediately exit
    --failfast \
    "./..."
# Output file for reference in build stage for parallelization
RUN touch "./null"

###
# STAGE
###
FROM prepare as build
RUN mkdir -p "./static/"
# Run a build
RUN go build \
    # detect race conditions
    --race \
    # output file
    -o="./function_bin"
# Forces the test stage to run in parallel
COPY --from=test [ "/usr/root/function/null", "./null" ]

###
# STAGE
###
FROM alpine:${ALPINE_VERSION} as deploy
# Add non-root user and group
RUN addgroup --system --gid="2000" "nonroot"
RUN adduser --system --ingroup="nonroot" --uid="2000" "nonroot"
# Add standard CA certs
RUN apk add --upgrade --no-cache "ca-certificates"
WORKDIR "/usr/nonroot"

# Copy watchdog over
COPY --from=watchdog --chown="2000" [ "/fwatchdog", "./fwatchdog" ]
RUN chmod +x "./fwatchdog"
# Copy build
COPY --from=build --chown="2000" [ "/usr/root/function/function_bin", "./function_bin" ]
# Copy static files, if any
COPY --from=build --chown="2000" [ "/usr/root/function/static", "./static" ]

USER "2000"

ENV fprocess="./function_bin"
ENV mode="http"
ENV upstream_url="http://127.0.0.1:8082"
ENV prefix_logs="false"

CMD [ "./fwatchdog" ]
