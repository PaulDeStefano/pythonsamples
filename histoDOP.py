
from pylab import *
import csv

with open('skDOPDec2012.2.csv') as fh:
    reader = csv.reader( fh )
    count  = 0
    limit  = 10000000
    #limit  = 10000
    skipLines = 1

    data = { 'time':[] ,'posDOP':[], 'timeDOP':[] }
    try:
        for row in reader:
            # UNIXtime, PDOP, TDOP
            count = count + 1
            #print row
            if( count <= skipLines ):
                print "skipping..."
                continue
            [ time,posDOP,timeDOP ]= [ float(row[0]),float(row[1]),float(row[2]) ]
            #print time , posDOP, timeDOP
            data['time'].append( time )
            data['posDOP'].append( posDOP/10 )
            data['timeDOP'].append( timeDOP/10 )
            if( count >= limit ):
                print "NOTICE: Reached data limit"
                break
    except csv.Error, e:
        sys.exit('file %s, line %d: %s' % (filename, reader.line_num, e))

    #
    data
    # create histogram
    n, bins, patches = hist( data['posDOP'] ,bins=30, histtype='step', log=True)
    print n
    print bins
    title("Position Dilusion of Precision Factor Histogram: 1-31 January 2013")
    ylabel("Count")
    xlabel("Position Dilusion of Precision")
    xscale('log')
    #ylim(ymin=10)
    show()
    n, bins, patches = plt.hist( data['timeDOP'] ,bins=30 , histtype='step', log=True)
    print n
    print bins
    title("Time Dilusion of Precision Factor Histogram: 1-31 January 2013")
    ylabel("Count")
    xlabel("Time Dilusion of Precision Factor")
    xscale('log')
    #ylim(ymin=10)
    show()
