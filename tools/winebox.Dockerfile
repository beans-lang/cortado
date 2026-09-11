# What runs cortado's Windows build when there is no Windows.
#
# Wine, from Ubuntu's own package, in an amd64 container. Two things in here
# are not obvious and both were found the hard way:
#
#   * `wine64` is the loader, not a wrapper — Debian and Ubuntu put it at
#     /usr/lib/wine/wine64 and ship the `wine` script in a different package.
#   * **Wine needs a display even to build a window it never shows.** A
#     headless cortado run creates real HWNDs and never calls ShowWindow, and
#     without an X server Wine cannot load a display driver at all:
#     "Application tried to create a window, but no driver could be loaded."
#     So xvfb is here, and `tools/win32.sh` runs under `xvfb-run`.
FROM ubuntu:24.04
RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        wine64 xvfb xauth ca-certificates libx11-6 libxext6 libfreetype6 && \
    rm -rf /var/lib/apt/lists/*
ENV WINEDEBUG=-all
ENV WINEPREFIX=/wine
# The prefix is made at build time, so a run is the program and nothing else.
RUN xvfb-run -a /usr/lib/wine/wine64 wineboot --init 2>&1 | tail -2; \
    /usr/lib/wine/wineserver -w
