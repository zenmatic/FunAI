#!/bin/bash

PATH=/Applications/OpenTTD.app/Contents/MacOS:$PATH

SAVEDGAME=~/Documents/OpenTTD/save/med-desert.sav
SAVEDGAME=~/Documents/OpenTTD/save/small-desert.sav
SAVEDGAME=~/Documents/OpenTTD/save/small-island.sav
SAVEDGAME="$HOME/Documents/OpenTTD/save/small one.sav"
openttd -m null -s null -g "$SAVEDGAME" -d script=4
