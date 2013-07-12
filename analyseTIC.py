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
import matplotlib.ticker as ticker
import time
from datetime import datetime
from calendar import timegm
import argparse
from operator import sub

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
    valueFixedL = []
    offsetL = []
    timeFixedL = []

    utOffsetList= sorted( list(offsetDB['unixtime']) )
    offsetList = list(offsetDB['offset'])
    offsetDBlen = len(offsetList)
    dataSet.sort()
    dataLen = len(dataSet)
    coeff = 1
    if negOffset:
        # reverse sign of correction if set (default)
        coeff = -1

    print "Applying xPPSOffset Corrections..."

    # TODO: make sure data set is sorted
    """ 
    Take the first time value from each list and find the corresponding index
    in the other list.  Then, advace through both lists, checking equality,
    and applying offset corrections to the raw data.
    If the two times stop matching, the there is a discontinuity in the time
    values in one or both lists.  Calculate the difference between the time of
    the current index in each list with the previous element to see which list
    has the missing data.
    If it's the data set, it must be less than the allowed gap or else there is
    an error.  Skip ahead in the offset list or generate an error.  If it is
    the offset list that has a gap, skip ahead in the data list.
    
    """
    offsetPtr = 0
    dataPtr = 0
    while( dataPtr <= dataLen -1 and offsetPtr <= offsetDBlen -1 ) :
        # check where we are
        tm = dataSet[dataPtr][0]
        dataT = timegm( tm )
        offsetT = utOffsetList[offsetPtr]
        if ( offsetT == dataT ):
            # it's working
            val = dataSet[dataPtr][1]
            offsetVal = offsetList[offsetPtr]
            valFixed=(val + coeff*offsetVal)
            valueFixedL.append(valFixed)
            timeFixedL.append(tm)
            offsetL.append(offsetVal)
            dataPtr += 1
            offsetPtr += 1
        else :
            while( dataT != offsetT ):
                if( dataT < offsetT ):
                    dataPtr += 1
                else:
                    offsetPtr += 1
                if( dataPtr >= dataLen or offsetPtr >= offsetDBlen ):
                    break
                tm = dataSet[dataPtr][0]
                dataT = timegm( tm )
                offsetT = utOffsetList[offsetPtr]

        #logMsg('DEBUG: val:{} offset:{} fixed:{}'.format(str(val),str(offsetVal),str(valFixed)))
        #logMsg( "DEBUG: success")

    print "...done"
    #logMsg("DEBUG: doXPPS: "+str(type(offsetL)) )
    #logMsg("DEBUG: offsetList length: "+str(len(offsetL['offset'])) )
    return ( valueFixedL, offsetL , timeFixedL )

def plotDateOnAxis(axis=None, label="no label", x=None, y=None, fmt='', stddevLine=True, subMean=True, units='', mean=0, stddev=0):

        if not axis:
            raise Exception("ERROR: no axis for plotting")
        if x == None or y == None:
            raise Exception("ERROR: no data to plot")


        x = [ matplotlib.dates.date2num( datetime.utcfromtimestamp( timegm(t) ) ) for t in x ]
        if subMean:
            y = [ (d - mean) for d in y ]
        obj = axis.plot_date( x, y, fmt , xdate=True, ydate=False , label=label, tz='UTC')
        c = obj[0].get_color()

        # beautify
        axis.set_ylabel(label+' ('+units+')')
        #ax.text(0.8,0.8,r'$\pi this is a test$',transform = ax.transAxes)
        #at = AnchoredText(extraText, loc=1, frameon=True)
        #axis.add_artist( at )

        if subMean:
            ylineH = stddev/2
            ylineL = -stddev/2
        else:
            ylineH = mean + stddev/2
            ylineL = mean - stddev/2
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
        xSeries , ySeries , label , mean , stddev , units = xy
        tolRangeL.append( [mean+(3*stddev) ,mean-(3*stddev), stddev*5, stddev*0.5 ] )

    # assume we don't need any axes, to start
    need = 0
    for xy in xyT:
        # for each data set, see how many compatible ranges exist
        xSeries , ySeries , label , mean , stddev, units = xy
        compatCount = 0
        for r in tolRangeL:
            #logMsg("DEBUG: prepFigure: ",mean, r[0], r[1] , r[2], r[3] )
            if ( mean <= r[0] and mean >= r[1] and stddev < r[2] and stddev > r[3] ) :
                # then at least one other range is compatible
                compatCount += 1
        if compatCount < 2:
            # only 1 compatible axis, must be it's own.  we need a separate axis for it.
            #logMsg("DEBUG: prepFigure: found new independent data set")
            need += 1
            if need > len(axesList) :
                # need count too high, create a new axis
                #logMsg("DEBUG: prepFigure: added new axis")
                axesList.append( host.twinx() )

    return axesList

def plotDateHelper(title="no title",xyList=None):
    global numBins
    if xyList == None:
        raise Exception("ERROR: no data to plot")

    # pull the first data set
    xyT = xyList[0]
    xSeries , ySeries , mainLabel , mean , stddev , units = xyT
    #logMsg("DEBUG: plotDataHelper: mainLabel: ",mainLabel)
    #logMsg("DEBUG: plotDataHelper: mean: ",mean)

    startasc = time.asctime(xSeries[0])
    endasc = time.asctime(xSeries[len(xSeries)-1])

    # start plot
    host = host_subplot(111)
    axisL = prepFigure(host,xyList)

    for xy, axx , fmt in zip( xyList , axisL , ['bo','go','yo'] ):
        # for each pair of x and y series
        # pull out x and y
        xSeries , ySeries , label , mean, stddev , units = xy
        extraText = r' $\sigma$'+'={0:.2G},$\mu=${1:.2G}'.format(stddev,mean)
        #logMsg("DEBUG: plotDataHelper: adding data labeled: "+label)
        # plot on date axis
        plotDateOnAxis(axis=axx, x=xSeries,y=ySeries, label=label+extraText , subMean=False, fmt=fmt, units=units, mean=mean, stddev=stddev)

    host.set_xlabel("Time: "+startasc+" - "+endasc)
    host.set_title(title)
    plt.setp(host.xaxis.get_majorticklabels(), rotation=30)
    plt.legend().get_frame().set_alpha(0.8)
    plt.draw()
    print("Showing values: "+title)
    #plt.show()
    
    # histograms
    for xy in xyList:
        fig2 = plt.figure()
        xSeries , ySeries , label , mean, stddev, units = xy
        logMsg("DEBUG: plotDataHelper: hist: label: "+label,mean,stddev)
        # plot histogram of values series
        ax = fig2.add_subplot(111, yscale='log')
        n, bins, patches = ax.hist( ySeries, numBins , label=label)
        ax.set_xlabel(str(numBins)+" bins of "+label+' ('+units+')')
        ax.set_ylabel("Counts in bin")
        extraText = r' $\sigma$'+'={0:.2G}'.format(stddev)
        extraText += r',$\mu$'+'={0:.2G}'.format(mean)
        fig2.suptitle(title+": Histogram of "+label+": "+extraText)
        print("Showing histogram of values:"+label+extraText)
        #plt.show()
        del(fig2)

    plt.show()

def getStats( timeL, valueL ):
    # stats
    mean, stddev = None, None
    mean = np.mean(valueL)
    stddev = np.std(valueL)
    
    # display epoch
    startasc = time.asctime(timeL[0])
    startUNIX = str( timegm(timeL[0]) )
    endasc = time.asctime(timeL[len(timeL)-1])
    endUNIX = str( timegm(timeL[len(timeL)-1]) )
    print 'epoch start: '+startasc+' '+startUNIX
    print 'epoch end  : '+endasc+' '+endUNIX

    return mean, stddev, startasc, startUNIX, endasc, endUNIX

def analyseSet(dataSet,label='label',title="title", units=''):
    global numBins, description, maxEpochGap
    global offsetDB, offsetFile

    # separate data into columns
    timeL , valueL = [],[]

    if len(offsetDB):
        """ apply offsets """
        ( valueL , offsetL , timeL ) = doXPPSCorrections( dataSet )
        label="corrected "+label

    else:
        """ do nothing else"""
        for t,val in dataSet:
            timeL.append(t)
            valueL.append(val)

    mean, stddev, startasc, startUNIX, endasc, endUNIX = getStats( timeL,valueL )
    xyTuple = ( timeL, valueL, label, mean, stddev , units )
    #logMsg("DEBUG: ", type(xyTriple) )

    #print("DEBUG: length of values: {}".format(len(valueL)) )
    #print("DEBUG: length of fixed values: {}".format(len(valueFixedL)) )

    plotDateHelper(title=title, xyList=[ xyTuple ] )

    ## Find first differences
    logMsg("NOTICE: calculating first differences")
    a,b = 0,1
    firstDiffL =  []
    while b <= len(valueL)-1 :
        firstDiffL.append( (valueL[a]-valueL[b]) )
        a+=1
        b+=1
    xL,yL = zip( *zip(timeL, firstDiffL) )
    mean, stddev, startasc, startUNIX, endasc, endUNIX = getStats( xL,yL )
    #xyTuple = ( xL, yL, label, mean, stddev, units )
    #plotDateHelper(title="First Differeces: "+title, xyList=[ xyTuple ] )
    xyTuple = ( xL, yL, "Frac Freq Departure", mean, stddev, "PPB" )
    plotDateHelper(title=title, xyList=[ xyTuple ] )

def doStuff() :
    global inputFiles
    global shiftOffset

    goodCount = 0
    lineCount = 0
    limit = 100000000
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
        for line in (csv.reader(file,delimiter=' ')):
            #iso8601, delta , unixtime = list(line)
            fields = list(line)
            #logMsg(str(fields))
            iso8601 = fields[0]
            delta = fields[1]
            nsec = fields[3]
            if len(fields) >= 4 :
                unixtime = int(fields[2])
                deltaTime = datetime.utcfromtimestamp(unixtime).timetuple()
            else:
                if not shiftOffset == float(0):
                    raise Exception("ERROR: cannot apply time shift to xPPSoffset data without unixtime in field #4")
                deltaTime = time.strptime(iso8601+' UTC', "%Y-%m-%dT%H:%M:%S %Z")
            #logMsg("DEBUG: doStuff: time spec:", type(deltaTime))
            if prevTime and deltaTime < prevTime :
                raise Exception("time went backward, out of order or error? prev={} current={}".format(prevTime,deltaTime) )
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
    
    ## Find breaks for each series
    i1 = 0
    goodData = []
    dataEpochList = []
    
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
            # store data epochs in epoch lists
            dataEpochList.append(goodData)
            goodData = []
        else :
            # okay, these points are part of a contigous series
            # store the first point only
            goodData.append( dataArray[i1] )
        # incriment index
        i1 += 1
    #end while loop#
    # here all but the last data point has been processed, don't forget it
    # we assume it's good
    goodData.append(dataArray[i1])

    # store last data and diff lists in the epoch lists as the last epoch of their series
    dataEpochList.append(goodData)
    # what did we find?
    print "NOTICE: epochs found: " + repr(len(dataEpochList))

    # load offset list if it exist
    if not len(offsetDB):
        # if we haven't the offset data loaded, already, check to see
        # if we can load it from a file
        if offsetFile:
            # we can load it, so try
            loadOffsets(offsetFile)
            #logMsg("DEBUG: analyseSet: ", str(offsetDB[...,0]) )
            if not len(offsetDB):
                raise Exception('XPPSOffset values NOT loaded!',len(offsetDB))

    ## Plot data, differences, and histograms for each epoch
    epochN = 0;
    for dataSet in dataEpochList:
        epochN = epochN +1
        print "Analysing epoch: " + str(epochN)
        print "Analysing original measurements"
        analyseSet( dataSet , label='dT', title=description, units='ns')

def loadOffsets(file):
    """ Retreive xPPSOffset values from file.
        Assumed format is
                <ISO8601 date/time>,<offset>,<UNIXtime>,4,5,6,7,8
        This matches sbf2offset.py output format
    """
    global offsetDB
    # TODO shiftOffset is applied to the time off the xPPSOffset values as they are imported
    # it would be more accurate to apply this to the TIC measurements, as that
    # time value is suspected to be the source of the uncertainty.
    global shiftOffset

    print("NOTICE: trying to import offset data...")
    with open(file,'r') as fh:
        offsetDB = np.loadtxt(fh
#                , dtype={'names': ('asctime','offset','unixtime','four','five','six','seven','eight')
#                , 'formats':('S19',np.float64,np.float64,'i4','i4','f4','f4','i4')}
                , dtype={'names': ('asctime','offset','unixtime')
                , 'formats':('S19',np.float64,np.float64,'i4')}
                , converters={2: lambda u: int(float(u))+shiftOffset }
                , delimiter=',')
        #logMsg("DEBUG: loadOffsetdb: ",len(offsetDB['offset'])) 
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
parser.add_argument('--shiftOffset', '-s', nargs='?', default=0.0, help='shift time of xPPSOffset corrections wrt. TIC measurements by this many seconds')
args = parser.parse_args()
inputFiles = args.fileList
description = args.desc
maxEpochGap = float(args.gap)
offsetFile = args.offsets
negOffset = args.negOffset
numBins = args.histbins
shiftOffset = float(args.shiftOffset)
#print("DEBUG: negOffset:" + str(negOffset) )

# xPPSoffset data
offsetDB = []

if __name__ == "__main__" :
    doStuff()
