Static audio-only FFmpeg builds
===============================

This project contains scripts for small (4-5MB) static, audio-only FFmpeg and FFProbe builds that can be used to open, inspect and transcode audio files.

These binaries support the following capabilities

Filters:
* Volume
* Loudnorm
* Highpass
* Lowshelf
* Fade


Builds are all 64-bit and compiled using GitHub Actions. You can find the built binaries on the Releases page.

Supported platforms:

  - Linux
      * `x86\_64-linux-gnu`
  - Windows
      * `x86\_64-w64-mingw32`
  - macOS
      <!-- * `x86_64-apple-macos10.9` (macOS Mavericks and newer on Intel CPU) -->
      * `arm64-apple-macos11` (macOS Big Sur and newer on Apple M series CPUs)

This repo is a fork of https://github.com/acoustid/ffmpeg-build