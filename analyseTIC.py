#!/usr/bin/python2.7
""" analyse.py
    Analyse ToF TIC data.

    Copyright (C) 2013 Paul R. DeStefano

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <http://www.gnu.org/licenses/>.
"""
import csv
import sys
import numpy as np
import matplotlib
from matplotlib import rc
#matplotlib.use('svg')
import matplotlib.pyplot as plt
from matplotlib.offsetbox import AnchoredOffsetbox, TextArea
from mpl_toolkits.axes_grid1 import host_subplot
import mpl_toolkits.axisartist as AA
import time
from datetime import datetime
from calendar import timegm
import argparse

class AnchoredText( AnchoredOffsetbox ):
    def __init__(self, s, loc, pad=0.4, borderpad=0.5, prop=None, frameon=True):
        #self.txt = TextArea(s, minimumdecent=False)
        self.txt = TextArea(s)
        super(AnchoredText,self).__init__(loc,pad=pad,borderpad=borderpad,
                                            child=self.txt,
                                            prop=prop,
                                            frameon=frameon)

def logMsg(s, *args):
    #print("DEBUG: logMsg called")
    if args:
        for a in args:
            s += (" "+str(a))
    print >> sys.stderr , str(s)

def doXPPSCorrections(dataSet):
    """ Apply xPPSOffset values to the given (TIC) data set

        returns [ list of corrections , list of matching offsets ]
    """
    global offsetDB
    global negOffset
    #print "DEBUG: offsetDB is" , len(offsetDB)
    valueFixedL = []
    offsetL = []

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
        offsetL.append(offsetVal)
        #print 'DEBUG: val:{} offset:{} fixed:{}'.format(val,offsetVal,valFixed)
        #print "DEBUG: success"

    #logMsg("DEBUG: doXPPS: "+str(type(offsetL)) )
    return valueFixedL, offsetL

def plotDateOnAxis(axis=None, label="no label", x=None, y=None, fmt='o', stddevLine=True, subMean=True):

        if not axis:
            raise Exception("ERROR: no axis for plotting")
        if x == None or y == None:
            raise Exception("ERROR: no data to plot")


        mean = np.mean(y)
        stddev = np.std(y)
        extraText = r'$\sigma$'+'={0:.2G}'.format(stddev)
        label += ' '+extraText
        x = [ matplotlib.dates.date2num( datetime.utcfromtimestamp( timegm(t) ) ) for t in x ]
        if subMean:
            y = [ (d - mean) for d in y ]
        obj = axis.plot_date( x, y, fmt , xdate=True, ydate=False , label=label, tz='UTC')
        c = obj[0].get_color()

        # beautify
        axis.set_ylabel(label)
        #ax.text(0.8,0.8,r'$\pi this is a test$',transform = ax.transAxes)
        # legend.get_frame().set_alpha(0.5)
        #at = AnchoredText(extraText, loc=1, frameon=True)
        #axis.add_artist( at )

        if subMean:
            ylineH = stddev/2
            ylineL = -stddev/2
        else:
            ylineH = mean + stddev
            ylineL = mean - stddev
        if stddevLine:
            axis.axhline(y=ylineH, alpha=0.5, color=c)
            axis.axhline(y=ylineL, alpha=0.5, color=c)

def prepFigure(host=None, xyT=None) :
    """ Check sets of data for compatibility on a single plot
        Return a list of "parasite" axes
    """
    if xyT == None:
        raise Exception("ERROR: prepFigure: no data to plot")

    # start with just the host figure
    axesList = [ host ]

    tolRangeL = []
    for xy in xyT:
        # for each data set, define a tolerance range
        xSeries , ySeries , label , mean , stddev = xy
        tolRangeL.append( [mean+(3*stddev) ,mean-(3*stddev), stddev*5, stddev*0.5 ] )

    # assume we don't need any axes, to start
    need = 0
    for xy in xyT:
        # for each data set, see how many compatible ranges exist
        xSeries , ySeries , label , mean , stddev = xy
        compatCount = 0
        for r in tolRangeL:
            logMsg("DEBUG: prepFigure: ",mean, r[0], r[1] , r[2], r[3] )
            if ( mean <= r[0] and mean >= r[1] and stddev < r[2] and stddev > r[3] ) :
                # then at least one other range is compatible
                compatCount += 1
        if compatCount < 2:
            # only 1 compatible axis, must be it's own.  we need a separate axis for it.
            logMsg("DEBUG: prepFigure: found new independent data set")
            need += 1
            if need > len(axesList) :
                # need count too high, create a new axis
                logMsg("DEBUG: prepFigure: added new axis")
                axesList.append( host.twinx() )

    return axesList

def plotDateHelper(title="no title",xyList=None):
    global numBins
    if xyList == None:
        raise Exception("ERROR: no data to plot")

    # pull the first data set
    xyT = xyList[0]
    xSeries , ySeries , mainLabel , mean , stddev = xyT
    logMsg("DEBUG: plotDataHelper: mainLabel: ",mainLabel)
    logMsg("DEBUG: plotDataHelper: mean: ",mean)

    startasc = time.asctime(xSeries[0])
    endasc = time.asctime(xSeries[len(xSeries)-1])

    # start plot
    #fig1 = plt.figure()
    #ax = fig1.add_subplot(1,1,1)
    host = host_subplot(111, axes_class=AA.Axes)
    plt.subplots_adjust(right=0.75)
    axisL = prepFigure(host,xyList)

    for xy, ax in zip( xyList , axisL ):
        # for each pair of x and y series
        # pull out x and y
        xSeries , ySeries , label , mean, stddev = xy
        logMsg("DEBUG: plotDataHelper: adding data labeled: "+label)
        # plot on date axis
        plotDateOnAxis(axis=ax, x=xSeries,y=ySeries, label=label , subMean=False)

    #axis.axis( ymin = -1 * stddev, ymax = 1*stddev)
    #ax.set_ylabel(mainLabel+" - mean of "+str(mean)+" (s)")
    host.set_ylabel(mainLabel)
    host.set_xlabel("Time: "+startasc+" - "+endasc)
    host.legend().get_frame().set_alpha(0.5)
    #ax.autofmt_xdate()
    #ax.suptitle(title)
    #plt.figure().suptitle(title)
    plt.setp(host.xaxis.get_majorticklabels(), rotation=30)
    logMsg("DEBUG: plotDataHelper: showing values")
    plt.show()
    
    # histograms
    for xy in xyList:
        fig2 = plt.figure()
        xSeries , ySeries , label , mean, stddev = xy
        # plot on date axis
        # plot histogram of values series
        ax = fig2.add_subplot(111, yscale='log')
        n, bins, patches = ax.hist( ySeries, numBins , label=label)
        #hist, binEdges = np.histogram( ySeries, numBins)
        #print hist
        #print n, bins, patches
        ax.set_xlabel(str(numBins)+" bins of "+label)
        ax.set_ylabel("Counts in bin")
        #ax.legend()
        # legend.get_frame().set_alpha(0.5)
        fig2.autofmt_xdate()
        fig2.suptitle("Histogram of "+label)
        print("showing histogram of values")
        plt.show()


def analyseSet(dataSet,label='label',title="title"):
    global numBins, description, maxEpochGap

    # separate data into columns
    timeL , valueL = [],[]
    for t,val in dataSet:
        timeL.append(t)
        valueL.append(val)

    # stats
    mean, stddev = None, None
    mean = np.mean(valueL)
    stddev = np.std(valueL)

    xyTriple = [timeL,valueL,'dT (ns)']
    xyTuple = ( timeL, valueL, 'dT (ns)', mean, stddev )
    #logMsg("DEBUG: ", type(xyTriple) )

    # display epoch
    startasc = time.asctime(timeL[0])
    startUNIX = str( timegm(timeL[0]) )
    endasc = time.asctime(timeL[len(timeL)-1])
    endUNIX = str( timegm(timeL[len(timeL)-1]) )
    print 'epoch start: '+startasc+' '+startUNIX
    print 'epoch end  : '+endasc+' '+endUNIX
    label = "Date "+startasc+" - "+endasc

    #print("DEBUG: length of values: {}".format(len(valueL)) )
    #print("DEBUG: length of fixed values: {}".format(len(valueFixedL)) )

    # basic plot
    plotDateHelper(title=title,xyList=[ xyTuple ])

    if not len(offsetDB):
        global offsetFile
        if offsetFile:
            # perform xPPSOffset corrections, if we have them
            loadOffsets(offsetFile)
            if not len(offsetDB):
                raise Exception('XPPSOffset values NOT loaded!',len(offsetDB))

        # show data with offset to compare
        valueFixedL , offsetL = doXPPSCorrections( dataSet )
        logMsg("DEBUG: analyse: valueFixedL:"+str(len(valueFixedL)) )
        logMsg("DEBUG: analyse: offsetL:"+str(len(offsetL)) )
        xyList = [ xyTuple, [timeL,offsetL,'xPPSoffset', np.mean(offsetL),np.std(offsetL)] ]
        plotDateHelper(title=title, xyList=xyList)

        # show applied offssets
        meanFixed = np.mean(valueFixedL)
        stddevFixed = np.std(valueFixedL)
        print "adjusted mean:", meanFixed
        print "adjusted stddev:", stddevFixed
        xyList = [ xyTuple, [timeL,valueFixedL,'xPPSoffset', np.mean(valueFixedL),np.std(valueFixedL)] ]
        plotDateHelper(title=title, xyList=xyList )

def doStuff() :
    global inputFiles

    goodCount = 0
    lineCount = 0
    limit = 10000000
    #limit = 1000000
    bufLimit = 10
    dataArray = []
    dataBuffer = []
    ssList = []
    ssLimit = bufLimit
    prevTime = None
    good = True
    for f in inputFiles:
        print "NOTICE: working on file: " + f
        file = open(f)
        for line in (csv.reader(file)):
            #print line
            #date, hms, delta , unixtime = list(line)
            fields = list(line)
            date = fields[0]
            hms = fields[1]
            delta = fields[2]
            if len(fields) > 3 :
                unixtime = float(fields[3])
                deltaTime = datetime.utcfromtimestamp(unixtime).timetuple()
            else:
                deltaTime = time.strptime(date+' '+hms+' UTC', "%Y/%m/%d %H:%M:%S %Z")
            #logMsg("DEBUG: doStuff: time spec:", type(deltaTime))
            if prevTime and deltaTime < prevTime :
                raise Exception("time went backward, out of order or error?")
            # convert to high precision float
            #delta = np.float64(delta)
            delta = float(delta)/10**-9
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
    
    print "NOTICE: Finished processing all input files"
    #print "DEBUG: len(dataBuffer): " + repr(len(dataBuffer))
    #print "DEBUG: len(dataArray): " + repr(len(dataArray))
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
    #print "DEBUG: first difference epochs found: " + repr(len(diffEpochList))
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
        offsetDB = np.loadtxt(fh
                ,dtype={'names': ('asctime','offset','unixtime')
                ,'formats':('S19',np.float64,np.float64)}
                , delimiter=',')
        #print("DEBUG: " + str(offsetDB.shape) )
        #print("DEBUG: " + str(offsetDB) )
        #print("DEBUG: " + str(offsetDB.dtype) )
        #print("DEBUG: " + str(offsetDB['unixtime']) )
        #print("DEBUG: " + str(offsetDB['offset']) )
        #i = list(offsetDB['unixtime']).index(1365551993)
        #print offsetDB[i]['offset']
    #print("DEBUG: imported {} offset values".format(len(offsetDB)) )
    print("NOTICE: ...done ")


## MAIN ##
#print "DEBUG: input files:" + repr(inputFiles)
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

if __name__ == "__main__" :
    doStuff()
