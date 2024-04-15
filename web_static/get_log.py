#!/usr/bin/env python3
import time
import calendar
import sys

#--- set conditions below 
matches = ['Error', 'error', 'Exception', 'failed', 'Unhandled', 'err', 'Err']
# ---

pattern = "%Y/%m/%d%H:%M:%S"

source = sys.argv[1]
report = sys.argv[2]
last_hrs = sys.argv[3]

# shift =  time.timezone
shift = 0
now = time.time()

def convert_toepoch(pattern, stamp):
    """
    function to convert readable format (any) into epocherror
    """
    return int(time.mktime(time.strptime(stamp, pattern)))

with open(source) as infile:
    with open(report, "wt") as outfile:
        for l in infile:
            try:
                # parse out the time stamp, convert to epoch
                stamp = "".join(l.split()[:2])
                tstamp = convert_toepoch(pattern, stamp)
                # set the conditions the line has to meet
                if now - tstamp - shift <= int(last_hrs)*3600:
                    if any([s in l for s in matches]):
                        outfile.write(l)
            except (IndexError, ValueError):
                pass
