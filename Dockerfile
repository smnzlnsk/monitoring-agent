# syntax=docker/dockerfile:1
#
FROM golang:1.23-alpine AS builder

ENV GO111MODULE=on
ENV CGO_ENABLED=0

RUN apk add --no-cache git make

WORKDIR /app

COPY ./config/opentelemetry-collector-builder/manifest.yaml ./
COPY internal/ ./internal
COPY go.mod go.sum ./

RUN go mod download && \ 
  go install go.opentelemetry.io/collector/cmd/builder@latest

RUN builder --config=manifest.yaml --skip-strict-versioning

FROM alpine:latest

WORKDIR /otel

COPY --from=builder /app/build/agent .

ENTRYPOINT [ "./agent", "--config=opentelemetry-config.yaml" ]
