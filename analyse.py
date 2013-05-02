import csv
import numpy as np
import matplotlib
#matplotlib.use('svg')
import matplotlib.pyplot as plt
from array import array
import matplotlib.mlab as mlab
import time

file = open('input.dat')
goodCount = 0
lineCount = 0
limit = 10000000
limit = 1000000
bufLimit = 10
dataArray = []
dataBuffer = []
ssList = []
ssLimit = bufLimit
good = True
for line in (csv.reader(file)):
    #print line
    date, hms, delta = list(line)
    deltaTime = time.strptime(date+' '+hms, "%Y/%m/%d %H:%M:%S")
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

print "NOTICE: Finished processing input"
print "DEBUG: len(dataBuffer): " + repr(len(dataBuffer))
print "DEBUG: len(dataArray): " + repr(len(dataArray))
dataArray = dataArray + dataBuffer

# find first differences
i1 = 0
i2 = 1
firstDiffList = []
diffEpochList = []

while i1 <= len(dataArray) -2 :
    first = dataArray[i1]
    firstTime = time.mktime(first[0])
    second = dataArray[i2]
    secondTime = time.mktime(second[0])
    while ( i2 + 1 <= len(dataArray) -1 ) and  (first[0] == second[0]) :
        i2 += 1
        print "WARNING: possible duplicate: i2: " + repr(i2) + ": " + repr(firstTime) + " & " + repr(secondTime)
        second = dataArray[i2]
        secondTime = time.mktime(second[0])
    # here, i2 will be the largest index in the array slice with the same timestamp as index i1
    if i2-i1 > 2 :
        # more than 2 points with same timestamp, discard all
        del(dataArray[i1:i2])
        print "ERROR: too many measurements with the same timestamp: " + repr(firstTime) + " & " + repr(secondTime)
        i1 = i2+1
        i2 = i1+1
        continue
    elif i2-i1 == 2 :
        # only two consecutive data points with the same timestamp
        if first[1] == second [1] :
            # same data too; statistically improbable, discard
            # dont' have to check three for this, as they would get caught by previous check anyway
            print "ERROR: duplicate measurement: " + repr(first[1]) + " & " + repr(second[1])
            i1 = i2+1
            i2 = i1+1
            continue

    # okay, these points are not obviously bad

    # check for missing data
    firstTime = time.mktime(first[0])
    secondTime = time.mktime(second[0])
    if firstTime + 1 < secondTime :
        # stop here, make new series
        print "WARNING: missing data between " + repr(firstTime) + " & " + repr(secondTime)
        diffEpochList.append(firstDiffList)
        firstDiffList = []
    else :
        # okay, these points are part of a contigous series
        # calculate & store diff
        #diff = []
        diff = [ first[0] , ( second[1] - first[1] ) ]
        #print "DEBUG: frist diff = " + repr(diff)
        firstDiffList.append( diff )

    # next pair of points
    i1 += 1
    i2 += 1

diffEpochList.append(firstDiffList)


"""
while i2 < len(dataArray) :
    first = dataArray[i1]
    second = dataArray[i2]
    #print "DEBUG: p1 = " + repr( first )
    #print "DEBUG: p2 = " + repr( second )
    # check for duplicates
    firstTime = time.mktime(first[0])
    secondTime = time.mktime(second[0])
    if first[0] == second[0]:
        print "WARNING: possible duplicate: i1: " + repr(i1) + ": " + repr(firstTime) + " & " + repr(secondTime)
        # scan ahead
        i3 = i2+1
        while i3 < len(dataArray) and first[0] == dataArray[i3][0] :
            # found thrid data point with same time
            i3 += 1
        if i3
        if first[1] == second[1]:
            print "ERROR: duplicate measurement: " + repr(first[1]) + " & " + repr(second[1])
            # skip both data points
            i1 = i2 + 1
            i2 += 2
            continue

    # check for missing data
    if firstTime + 1 < secondTime :
        print "WARNING: missing data between " + repr(firstTime) + " & " + repr(secondTime)

    # calculate & store diff
    diff = []
    diff = [ first[0] , ( second[1] - first[1] ) ]
    #print "DEBUG: frist diff = " + repr(diff)
    firstDiffList.append( diff )
    i1 += 1
    i2 += 1
"""

# Plot differences
print "NOTICE: epochs found: " + repr(len(diffEpochList))
for diffSet in diffEpochList :
    print "Showing Epoch #" + repr(diffEpochList.index(diffSet) + 1)
    x = [time.mktime( d[0] ) for d in diffSet ]
    y = [d[1] for d in diffSet]
    # plot data in this series
    plt.plot( x, y, 'bo' )
    plt.show()
    # plot histogram of first differences in this series
    n, bins, patches = plt.hist( [ d[1] for d in firstDiffList ], 100 )
    #print n, bins, patches
    plt.show()
    

deltaArray = [ dd[1] for dd in dataArray ]
mean = np.mean(deltaArray)
print "mean:", mean
median = np.median(deltaArray)
print "median:", median
stddev = np.std(deltaArray)
print "stddev:", stddev

hist, binEdges = np.histogram(deltaArray, 100)
print hist

n, bins, patches = plt.hist(deltaArray, 100 ,range=[mean-6*stddev,mean+6*stddev] )
print n, bins, patches
plt.show()

# error in PolaRx PPS pulse is +- 10ns
# error in TrueTime PPS pluse is
# error in TIC is 500ps + timebase*interval + .05*trigger+.15
#plt.plot(deltaArray, 'ro')
plt.plot( [ time.mktime(d[0]) for d in dataArray ], [ d[1] for d in dataArray ], 'ro')

#plt.errorbar( [time.mktime(d[0]) for d in dataArray],
#              [d[1] for d in dataArray],
#              fmt='ro', antialiased=False, yerr=10E-9,
#              ecolor='blue')
#              errorevery=100, ecolor='blue')
xmin = time.mktime(dataArray[0][0])
print repr(xmin)
xmax = time.mktime(dataArray[len(dataArray)-1][0] )
print repr(xmax)
ymin = mean-6*stddev
ymax = mean+6*stddev
#plt.axis(xmin=xmin ,xmax=xmax, ymin=ymin, ymax=ymax)
#plt.axis(xmin=0 ,xmax=10, ymin=0, ymax=10)

plt.show()
