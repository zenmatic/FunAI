#!/bin/bash

SAVEDGAME=~/Documents/OpenTTD/save/med-desert.sav
SAVEDGAME=~/Documents/OpenTTD/save/small-desert.sav
SAVEDGAME=~/Documents/OpenTTD/save/small-island.sav
openttd -m null -s null -g $SAVEDGAME -d script=4
