# syntax=docker/dockerfile:1
#
FROM golang:1.23-alpine AS builder

ENV GO111MODULE=on
ENV CGO_ENABLED=0

RUN apk add --no-cache git make

WORKDIR /app

COPY config/opentelemetry-collector-builder/dev-manifest.yaml ./
COPY config/opentelemetry-collector/opentelemetry-config.yaml ./
COPY go.mod go.sum ./

RUN go mod download && \ 
  go install go.opentelemetry.io/collector/cmd/builder@v0.109.0

RUN builder --config=remote-manifest.yaml --skip-strict-versioning

FROM alpine:latest

WORKDIR /otel

COPY --from=builder /app/build/monitoringagent .
COPY --from=builder /app/opentelemetry-config.yaml .

ENTRYPOINT [ "./monitoringagent", "--config=opentelemetry-config.yaml" ]
