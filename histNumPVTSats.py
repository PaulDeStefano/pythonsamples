
from pylab import *
import csv

with open('skPVTGeoNumSVUsed.csv') as fh:
    reader = csv.reader( fh )
    count  = 0
    limit  = 10000000
    #limit  = 10000
    skipLines = 1
    badcount = 0

    data = { 'time':[] ,'numsats':[] }
    try:
        for row in reader:
            # GPSTime, # Sats used
            count = count + 1
            #print row
            if( count <= skipLines ):
                print "skipping..."
                continue
            [ time,numsats]= [ float(row[0]),int(row[1]) ]
            #print time , posDOP, timeDOP
            if( numsats == 255 ):
                badcount = badcount+1
                continue
            data['time'].append( time )
            data['numsats'].append( numsats )
            if( count >= limit ):
                print "NOTICE: Reached data limit"
                break
    except csv.Error, e:
        sys.exit('file %s, line %d: %s' % (filename, reader.line_num, e))

    #
    print "badcount: ", badcount
    # create histogram
    n, bins, patches = hist( data['numsats'] ,bins=[1,2,3,4,5,6,7,8,9,10,11,12,13,14.15,16,17,18,19,20] , histtype='step', log=True)
    print n
    print bins
    title("Number of Satellites used in PVT Solution Histogram: 1-31 January 2013")
    ylabel("Count")
    xlabel("Number of Satellites")
    #xscale('log')
    #ylim(ymin=10)
    show()
