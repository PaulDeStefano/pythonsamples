
from pylab import *
import csv

with open('skCAcarrierToNoise.csv') as fh:
    reader = csv.reader( fh )
    count  = 0
    limit  = 100000000
    #limit  = 10000
    skipLines = 1
    badcount = 0

    data = { 'time':[] ,'CtoN0':[] }
    try:
        for row in reader:
            # GPSTime, # Sats used
            count = count + 1
            #print row
            if( count <= skipLines ):
                print "skipping..."
                continue
            [ time,ratio]= [ float(row[0]),float(row[1]) ]
            #print time , posDOP, timeDOP
            if( ratio == -3276.8 or ratio == -20000000000.0):
                badcount = badcount+1
                continue
            data['time'].append( time )
            data['CtoN0'].append(ratio  )
            if( count >= limit ):
                print "NOTICE: Reached data limit"
                break
    except csv.Error, e:
        sys.exit('file %s, line %d: %s' % (filename, reader.line_num, e))

    #
    print "badcount: ", badcount
    # create histogram
    n, bins, patches = hist( data['CtoN0'] ,bins=30, histtype='step', log=True)
    print n
    print bins
    title("CA Carrier to Noise Ratio Histogram: 1-31 January 2013")
    ylabel("Count")
    xlabel("Carrier to Noise Ratio (dB)")
    #xscale('log')
    #ylim(ymin=10)
    show()
