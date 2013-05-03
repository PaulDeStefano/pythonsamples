import csv
import numpy as np
import matplotlib
#matplotlib.use('svg')
import matplotlib.pyplot as plt
from array import array
import matplotlib.mlab as mlab
import time
import datetime
from calendar import timegm
import argparse

parser = argparse.ArgumentParser(description='find breaks in TIC data and analyse.')
parser.add_argument('fileList', nargs='+', help='intput files')
parser.add_argument('--desc', nargs='?', help='data description')
parser.add_argument('--gap', nargs='?', default=3, help='maximum gap tolerance (s) between epochs')
args = parser.parse_args()
inputFiles = args.fileList
description = args.desc
maxEpochGap = float(args.gap)

def analyseSet(dataSet,label='lablel',title="title"):
    timeL , valueL = [],[]
    for pair in dataSet:
        timeL.append(pair[0])
        valueL.append(pair[1])

    # show epoch
    startasc = time.asctime(timeL[0])
    startUNIX = str( timegm(timeL[0]) )
    endasc = time.asctime(timeL[len(timeL)-1])
    endUNIX = str( timegm(timeL[len(timeL)-1]) )
    print 'start: '+startasc+' '+startUNIX
    print 'end  : '+endasc+' '+endUNIX

    # simple stats
    mean = np.mean(valueL)
    print "mean:", mean
    median = np.median(valueL)
    print "median:", median
    stddev = np.std(valueL)
    print "stddev:", stddev

    # plot data in this series (-mean)
    x = [ matplotlib.dates.date2num( datetime.datetime.utcfromtimestamp( timegm(t) ) ) for t in timeL ]
    y = [ (d - mean) for d in valueL ]

    fig1 = plt.figure()
    ax = fig1.add_subplot(1,1,1)
    ax.plot_date( x, y, fmt='go' , xdate=True, ydate=False , label=label, tz='UTC')
    ax.axes.set_title(title)
    ax.set_xlabel("Time: "+startasc+' - '+endasc)
    ax.set_ylabel(label+" - mean of "+str(mean)+" (s)")
    ax.legend()
    fig1.autofmt_xdate()
    print("showing plot of values")
    plt.show()

    # plot histogram of values series
    fig2 = plt.figure()
    ax = fig2.add_subplot(1,1,1)
    n, bins, patches = ax.hist( valueL, 100 , label=label)
    #hist, binEdges = np.histogram( valueL, 100)
    #print hist
    #print n, bins, patches
    ax.axes.set_title("Histogram of "+title)
    ax.set_xlabel("Bins of "+label)
    ax.set_ylabel("Counts")
    ax.legend()
    print("showing histogram of values")
    plt.show()

    # replot histogram within range limited to 7 stddev of mean
    #n, bins, patches = plt.hist( valueL, 100, range=[mean-6*stddev,mean+6*stddev] , label=label)
    #plt.plot( x, y, 'bo' )
    #plt.legend()
    #print("showing limited histogram of dT")
    #plt.show()

    
def doStuff() :
    
    goodCount = 0
    lineCount = 0
    limit = 10000000
    #limit = 1000000
    bufLimit = 10
    dataArray = []
    dataBuffer = []
    ssList = []
    ssLimit = bufLimit
    prevTime = 0
    good = True
    for f in inputFiles:
        print "DEBUG: working on file: " + f
        file = open(f)
        for line in (csv.reader(file)):
            #print line
            date, hms, delta , unixtime = list(line)
            deltaTime = time.strptime(date+' '+hms+' UTC', "%Y/%m/%d %H:%M:%S %Z")
            if deltaTime < prevTime :
                raise Exception("time went backward, out of order or error?")
            # convert to high precision float
            #delta = np.float64(delta)
            delta = float(delta)
            data = [ deltaTime , delta ]
            #print repr(data)
            #print repr(delta)
            lineCount = lineCount + 1
        
            # for now, lets assume all are good
            goodCount = 1 + goodCount
            dataArray.append(data)
            if goodCount >= limit :
                break
            prevTime = deltaTime
    
    print "NOTICE: Finished processing input"
    print "DEBUG: len(dataBuffer): " + repr(len(dataBuffer))
    print "DEBUG: len(dataArray): " + repr(len(dataArray))
    dataArray = dataArray + dataBuffer

    # show all data
    print "Preview: ploting the complete raw dataset..."
    analyseSet(dataArray, label="dT", title="dT: "+description)
    print "...done."
    
    ## Find breaks and first differences for each series
    i1 = 0
    i2 = 1
    goodData = []
    dataEpochList = []
    firstDiffList = []
    diffEpochList = []
    
    while i1 <= len(dataArray) -2 :
        first = dataArray[i1]
        firstTime = timegm(first[0])
        second = dataArray[i2]
        secondTime = timegm(second[0])
        while ( i2 + 1 <= len(dataArray) -1 ) and  (dataArray[i1][0] == dataArray[i2][0]) :
            print "WARNING: possible duplicate: i2: " + repr(i2) + "time: " + repr(timegm(dataArray[i1][0])) + " & " + repr(timegm(dataArray[i2][0]))
            i2 += 1
#            second = dataArray[i2]
#            secondTime = timegm(second[0])

        # here, i2 will be the largest index in the array slice with the same timestamp as index i1
        if i2-i1 > 2 :
            # more than 2 points with same timestamp, discard all duplicates, keep first
            print "ERROR: too many measurements with the same timestamp: " + repr(timegm(dataArray[i1][0])) + " & " + repr(timegm(dataArray[i2][0]))
            del(dataArray[i1+1:i2+1])
            #raise Exception("too many consecutive data points with same timestamp")
            # after delete, dataArray is shorter.  i1 still points to the same value, but i2
            # points to a new data point.
            # So, just reset i2 to the next index
            i2 = i1+1
            # now, the indexes are sequential and point to consecutive data in the modified array
            # we logged an error, because this may not be the correct way to handle this error
            # we can simply go on from here without any extra flow changes
            # because we want to check for gaps, still, but we've elimitnated
            # the possiblity that we have duplcate data.
        elif i2-i1 == 2 :
            # only two consecutive data points with the same timestamp
            # at this point i1 and i2 have only one point between them, which has the same time as i1
            # check the data of i1 and the next one, backtracking a bit
            if dataArray[i1][1] == dataArray[i1+1][1] :
                # same data too; statistically improbable, probably an error, discard
                # dont' have to check three for this, as they would get caught by previous check anyway
                print "ERROR: duplicate measurement: " + repr(dataArray[i1][1]) + " & " + repr(dataArray[i1+1][1])
                del(dataArray[i1+1])
                # i1 still points to the same data, but
                # reset i2 to the next sequential index and go on
                i2 = i1+1
    
        ## okay, these points are not obviously bad
        # check for missing data, carve data set into epochs
        # reset first and second variables, things may have changed
        first = dataArray[i1]
        second = dataArray[i2]
        firstTime = timegm(first[0])
        secondTime = timegm(second[0])
        if firstTime + maxEpochGap < secondTime :
            # stop here, make new series
            print "WARNING: missing data between " + repr(firstTime) + " & " + repr(secondTime)
            # save first point to finish epoch
            goodData.append( dataArray[i1] )
            # store data and diff epochs in epoch lists
            dataEpochList.append(goodData)
            goodData = []
            diffEpochList.append(firstDiffList)
            firstDiffList = []
        else :
            # okay, these points are part of a contigous series
            # store the first point only
            goodData.append( dataArray[i1] )
            # calculate & store diff
            #diff = []
            diff = [ first[0] , ( second[1] - first[1] ) ]
            #print "DEBUG: frist diff = " + repr(diff)
            firstDiffList.append( diff )
    
        # next pair of points
        i1 = i2
        i2 = i1 + 1
    #end while loop#

    # store last data and diff lists in the epoch lists as the last epoch of their series
    dataEpochList.append(goodData)
    diffEpochList.append(firstDiffList)
    # what did we find?
    print "NOTICE: epochs found: " + repr(len(diffEpochList))
    print "NOTICE: epochs found: " + repr(len(dataEpochList))

    ## Plot data, differences, and histograms for each epoch
    epochN = 0;
    for dataSet, diffSet in zip( dataEpochList, diffEpochList ) :
        epochN = epochN +1
        print "Analysing epoch: " + str(epochN)
        print "Analysing original measurements"
        analyseSet( dataSet , "dT", "dT: "+description )
        print "Analysing first differences"
        analyseSet( diffSet , "dT1-dT2" , "First Differences: "+description )
        print "...done"
    
## MAIN ##
print "DEBUG: input files:" + repr(inputFiles)
doStuff()
