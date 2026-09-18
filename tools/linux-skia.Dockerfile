FROM debian:bookworm

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update -qq && apt-get install -y -qq --no-install-recommends \
    cmake g++ make pkg-config python3 ca-certificates \
    libegl-dev libgl-dev libfontconfig1-dev libfreetype6-dev libgl1-mesa-dri \
    && rm -rf /var/lib/apt/lists/*
