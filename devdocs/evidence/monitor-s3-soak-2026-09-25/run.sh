#!/bin/bash
cd /home/neo/frankH
W=/tmp/claude-1000/-home-neo-frankH/a8607ecd-ea8a-4535-8d1c-b5e028233fb8/scratchpad/flag
echo "compiler $(sha256sum compiler/pascal26 | cut -c1-12) tree $(git rev-parse --short HEAD)"
sudo -n -u neo -g dialout bash -c ". ~/esp/esp-idf/export.sh >/dev/null 2>&1; PXX=$PWD/compiler/pascal26 PXX_MAIN=$W/monitor240.npy tools/esp_flash.sh --project examples/esp32/monitor-s3 --port /dev/ttyACM0 --no-verify --seconds 2" > $W/build.log 2>&1
sudo -n -u neo -g dialout python3 $W/../rawcap.py 262 > $W/soak.raw 2>&1
echo "reports: $(grep -a -c '^#' $W/soak.raw)"
grep -a -E '^# *(1|2|3|5|10|30|60|120|180|240) ' $W/soak.raw
grep -a -E '^done|main\(\) returned' $W/soak.raw
echo FLAG-SOAK-COMPLETE
