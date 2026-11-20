FROM qbittorrentofficial/qbittorrent-nox:latest

USER root

RUN apk add --no-cache jq curl
