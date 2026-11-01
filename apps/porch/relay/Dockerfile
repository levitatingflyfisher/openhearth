# Build a static relayd binary; run it from scratch (no shell, no OS, no logs).
FROM docker.io/library/golang:1.25-alpine AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
ARG VERSION=dev
RUN CGO_ENABLED=0 go build -trimpath -ldflags="-s -w -X main.version=${VERSION}" -o /relayd ./cmd/relayd

FROM scratch
COPY --from=build /relayd /relayd
USER 65534:65534
EXPOSE 8080
ENTRYPOINT ["/relayd"]
