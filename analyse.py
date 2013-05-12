#!/usr/bin/python2.7
import csv
import numpy as np
import matplotlib
from matplotlib import rc
#matplotlib.use('svg')
import matplotlib.pyplot as plt
from matplotlib.offsetbox import AnchoredOffsetbox, TextArea
from array import array
import time
import datetime
from calendar import timegm
import argparse

rc('text',usetex=True)
#rc('font',family='serif')

parser = argparse.ArgumentParser(description='Find breaks in TIC data and analyse.')
parser.add_argument('fileList', nargs='+', help='TIC data files')
parser.add_argument('--desc', nargs='?', help='Description (title) for plots', default='DEFAULT DESCRIPTION')
parser.add_argument('-g', '--gap', nargs='?', default='3', help='Maximum gap/tolerance (s) between epochs')
parser.add_argument('--offsets', nargs='?', help='File continating xPPSoffset values (from sbf2offset.py)')
parser.add_argument('--addOffset', dest='negOffset', action='store_false', default=True, help='Boolean.  Add offset values to TIC measurements (dT)')
parser.add_argument('--subtractOffset', dest='negOffset', action='store_true', default=True, help='Boolean. Subtract offset values from TIC measurements (dT)')
parser.add_argument('--histbins', nargs='?', default=100, help='Number of bins in histograms')
args = parser.parse_args()
inputFiles = args.fileList
description = args.desc
maxEpochGap = float(args.gap)
offsetFile = args.offsets
negOffset = args.negOffset
numBins = args.histbins
#print("DEBUG: negOffset:" + str(negOffset) )

# xPPSoffset data
offsetDB = []

class AnchoredText( AnchoredOffsetbox ):
    def __init__(self, s, loc, pad=0.4, borderpad=0.5, prop=None, frameon=True):
        #self.txt = TextArea(s, minimumdecent=False)
        self.txt = TextArea(s)
        super(AnchoredText,self).__init__(loc,pad=pad,borderpad=borderpad,
                                            child=self.txt,
                                            prop=prop,
                                            frameon=frameon)

def doXPPSCorrections(dataSet):
    """ Apply xPPSOffset values to the given (TIC) data set
    """
    global offsetDB
    global negOffset
    #print "DEBUG: offsetDB is" , len(offsetDB)
    valueFixedL = []

    unixtList = list(offsetDB['unixtime'])
    offsetList = list(offsetDB['offset'])
    offsetDBlen = len(offsetDB)
    coeff = 1
    if negOffset:
        # reverse sign of correction if set (default)
        coeff = -1

    # A brute-force search of the full correction series was taking a long time.
    # We impliment a pointer than preserves the index of the last match, and prevents
    # the next match from having to re-compare previous matches.
    # This assumes both dataSet and offsetList are already nearly sorted.
    lastIndex = 0
    for t,val in dataSet:
        unixt = timegm(t)
        #print "DEBUG: searching for:",unixt
        if lastIndex > 10 :
            # backtrack a bit in case things are out of order slightly
            lastIndex -= 9
        while( lastIndex <= offsetDBlen-1 and not (unixt == unixtList[lastIndex]) ):
            #print "DEBUG: unixttime:",unixtList[lastIndex]
            lastIndex += 1
        if( lastIndex <= offsetDBlen-1 ):
            # success
            offsetVal = offsetList[lastIndex]
        else:
            # failure
            raise Exception("could not find value in offsetDB: "+str(unixt))
        # apply offset
        valFixed=(val + coeff*offsetVal/(1e09))
        valueFixedL.append(valFixed)
        #print 'DEBUG: val:{} offset:{} fixed:{}'.format(val,offsetVal,valFixed)
        #print "DEBUG: success"

    return valueFixedL

def analyseSet(dataSet,label='lable',title="title"):
    global numBins
    global description, maxEpochGap

    # separate data into columns
    timeL , valueL = [],[]
    for t,val in dataSet:
        timeL.append(t)
        valueL.append(val)

    # display epoch
    startasc = time.asctime(timeL[0])
    startUNIX = str( timegm(timeL[0]) )
    endasc = time.asctime(timeL[len(timeL)-1])
    endUNIX = str( timegm(timeL[len(timeL)-1]) )
    print 'epoch start: '+startasc+' '+startUNIX
    print 'epoch end  : '+endasc+' '+endUNIX

    # simple stats
    mean = np.mean(valueL)
    print "mean:", mean
    #median = np.median(valueL)
    #print "median:", median
    stddev = np.std(valueL)
    print "stddev:", stddev

    # perform xPPSOffset corrections, if we have them
    valueFixedL = []
    if len(offsetDB):
        valueFixedL = doXPPSCorrections( dataSet )
        print("DEBUG: "+repr(type(valueFixedL)) )
    meanFixed = np.mean(valueFixedL)
    stddevFixed = np.std(valueFixedL)
        
    print("DEBUG: length of values: {}".format(len(valueL)) )
    print("DEBUG: length of fixed values: {}".format(len(valueFixedL)) )

    # start plot
    fig1 = plt.figure()
    ax = fig1.add_subplot(1,1,1)
    # plot data in this series (-mean)
    x = [ matplotlib.dates.date2num( datetime.datetime.utcfromtimestamp( timegm(t) ) ) for t in timeL ]
    y = [ (d - mean) for d in valueL ]
    ax.plot_date( x, y, fmt='go' , xdate=True, ydate=False , label=label, tz='UTC')
    extraText = r'$\sigma$'+'={0:.2G}'.format(stddev)

    # beautify
    ax.axes.set_title(title)
    ax.set_xlabel("Time: "+startasc+' - '+endasc)
    ax.set_ylabel(label+" - mean of "+str(mean)+" (s)")
    at = AnchoredText(extraText, loc=1, frameon=True)
    ax.add_artist( at )
    #ax.text(0.8,0.8,r'$\pi this is a test$',transform = ax.transAxes)
    #ax.legend()
    # legend.get_frame().set_alpha(0.5)
    fig1.autofmt_xdate()
    print("showing plot of values")
    plt.show()

    # plot histogram of values series
    fig2 = plt.figure()
    ax = fig2.add_subplot(1,1,1)
    n, bins, patches = ax.hist( valueL, numBins , label=label)
    #hist, binEdges = np.histogram( valueL, numBins)
    #print hist
    #print n, bins, patches
    ax.axes.set_title("Histogram of "+title)
    ax.set_xlabel(str(numBins)+" bins of "+label)
    ax.set_ylabel("Counts")
    #ax.legend()
    # legend.get_frame().set_alpha(0.5)
    ax.add_artist( at )
    fig2.autofmt_xdate()
    print("showing histogram of values")
    plt.show()

    #  Plot offset corrected values
    fig3 = plt.figure()
    ax = fig3.add_subplot(1,1,1)
    print "mean:", meanFixed
    print "stddev:", stddevFixed
    y = [ (d - mean) for d in valueFixedL ]
    extraText = r'$\sigma$'+'={0:.2G}'.format(stddevFixed)
    ax.plot_date( x, y, fmt='bo' , xdate=True, ydate=False , label=label, tz='UTC')
    ax.axes.set_title('(adjusted) '+title)
    ax.set_xlabel("Time: "+startasc+' - '+endasc)
    ax.set_ylabel(label+" (adjusted) - mean of "+str(mean)+" (s)")
    #ax.legend()
    # legend.get_frame().set_alpha(0.5)
    at = AnchoredText(extraText, loc=1, frameon=True)
    ax.add_artist( at )
    fig3.autofmt_xdate()
    print("showing plot of fixed values")
    plt.show()

    # plot histogram of values series
    fig4 = plt.figure()
    ax = fig4.add_subplot(1,1,1)
    n, bins, patches = ax.hist( valueFixedL, numBins , label=label)
    #hist, binEdges = np.histogram( valueL, numBins)
    #print hist
    #print n, bins, patches
    ax.axes.set_title("(adjusted) Histogram of "+title)
    ax.set_xlabel(str(numBins)+" bins of "+label)
    ax.set_ylabel("Counts")
    #ax.legend()
    # legend.get_frame().set_alpha(0.5)
    ax.add_artist( at )
    fig4.autofmt_xdate()
    print("showing histogram of fixed values")
    plt.show()

    # replot both raw and fixed data together
    if len(valueFixedL):
        fig1 = plt.figure()
        ax = fig1.add_subplot(1,1,1)
        y = [ (d - mean) for d in valueL ]
        extraText = '('+r'$\sigma$'+'={0:.2G}'.format(stddev)+')'
        ax.plot_date( x, y, fmt='go' , xdate=True, ydate=False , label=label+" "+extraText, tz='UTC')
        y = [ (d - mean) for d in valueFixedL ]
        extraText = '('+r'$\sigma$'+'={0:.2G}'.format(stddevFixed)+')'
        ax.plot_date( x, y, fmt='bo' , xdate=True, ydate=False , label="adjusted "+label+" "+extraText, tz='UTC')
        ax.axes.set_title(title)
        ax.set_xlabel("Time: "+startasc+' - '+endasc)
        ax.set_ylabel(label+" (adjusted) - mean of "+str(mean)+" (s)")
        leg = ax.legend()
        leg.get_frame().set_alpha(0.7)
        fig1.autofmt_xdate()
        print("overploting fixed values")
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
            #date, hms, delta , unixtime = list(line)
            fields = list(line)
            date = fields[0]
            hms = fields[1]
            delta = fields[2]
            if len(fields) == 4 :
                unixtime = fields[3]
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
    #print "Preview: ploting the complete raw dataset..."
    #analyseSet(dataArray, label="dT", title="dT: "+description)
    #print "...done."
    
    ## Find breaks and first differences for each series
    i1 = 0
    goodData = []
    dataEpochList = []
    firstDiffList = []
    diffEpochList = []
    
    while( i1 <= (len(dataArray)-2) ):
        #print "DEBUG: i1: " + str(i1)
        #print "DEBUG: first : " + str(timegm(dataArray[i1][0])) + " value: " + str(dataArray[i1][1])
        #print "DEBUG: second: " + str(timegm(dataArray[i1+1][0])) + " value: " + str(dataArray[i1+1][1])

        while( (i1 < len(dataArray)-1-2) and (dataArray[i1][0] == dataArray[i1+2][0]) ) :
            #print "DEBUG: third : " + str(dataArray[i1+2][0]) + str(timegm(dataArray[i1+2][1]))
            # keep deleting the data two points ahead so long as it has the same time as i1,
            # since that is either out of order or three data points with the same time, which
            # shouldn't happen
            print "ERROR: too many measurements with the same timestamp: " + repr(timegm(dataArray[i1][0])) + " & " + repr(timegm(dataArray[i1+2][0]))
            del( dataArray[i1+2] )

        while ( (i1 < len(dataArray)-1-1) and (dataArray[i1][0] == dataArray[i1+2][0]) and (dataArray[i1][1] == dataArray[i1+1][1]) ) :
            # keep deleteing the next data point until duplicates are gone
            print "ERROR: found duplicate time: " + repr(timegm(dataArray[i1][0])) + " and value: " + repr(dataArray[i1][1])
            del( dataArray[i1+1] )

        ## okay, these points are not obviously bad
        # check for missing data, carve data set into epochs
        # reset first and second variables, things may have changed
        first = dataArray[i1]
        second = dataArray[i1+1]
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
        # incriment index
        i1 += 1
    #end while loop#
    # here all but the last data point has been processed, don't forget it
    # we assume it's good
    goodData.append(dataArray[i1])

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

def loadOffsets(file):
    """ Retreive xPPSOffset values from file.
        Assumed format is
                <ISO8601 date/time>,<offset>,<UNIXtime>
        This matches sbf2offset.py output format
    """
    global offsetDB

    print("NOTICE: trying to import offset data...")
    with open(file,'r') as fh:
        offsetDB = np.loadtxt(fh,dtype={'names': ('asctime','offset','unixtime'), 'formats':('S19',np.float64,np.float64)}, delimiter=',')
        #print("DEBUG: " + str(offsetDB.shape) )
        #print("DEBUG: " + str(offsetDB) )
        #print("DEBUG: " + str(offsetDB.dtype) )
        #print("DEBUG: " + str(offsetDB['unixtime']) )
        #print("DEBUG: " + str(offsetDB['offset']) )
        #i = list(offsetDB['unixtime']).index(1365551993)
        #print offsetDB[i]['offset']
    print("DEBUG: imported {} offset values".format(len(offsetDB)) )
    print("NOTICE: ...done ")

## MAIN ##
print "DEBUG: input files:" + repr(inputFiles)
if offsetFile:
    loadOffsets(offsetFile)
    if not len(offsetDB):
        raise Exception('XPPSOffset values NOT loaded!',len(offsetDB))
doStuff()
