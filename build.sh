# Autogenerated by LiteX / git: 7fccf9fc
set -e
set -x
yosys -l top.rpt top.ys
nextpnr-ecp5 --json top.json --lpf top.lpf --textcfg top.config --um5g-85k --package CABGA554 --speed 8 --timing-allow-fail --seed 1

echo ============
ecppack top.config --svf top.svf --bit top.bit --bootaddr 0
