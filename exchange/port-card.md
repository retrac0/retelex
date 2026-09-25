
# Port card

The port card.  Part of the switching fabric.  It sits behind the block
header.  It watches all the highways for its incoming bits, and constantly
rewrites its own output highway, multiplexing its slots.

# Signals

### block internal bus side


HA - in - the 64 A status bits multiplexed at 64 kHz 
HC[0..7] - in - the 8 highway lanes at 512 kHz
SLOT[0..2]
BLOCK[0..2]

TX_CLK - 64 KHz


### channel card side

TX_C, TX_A - data channel and associated A status bit output by the channel line
RX_C, RX_A - same but input from the port latches 

OPTION - the card option word
/ANS - answer
...TBD

bbb bss sss

