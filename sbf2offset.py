#!/usr/bin/python
""" sbf2offset.py
    Reads SBF binary data files and produces plain text file
    containing xPPSOffset data values

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
import time
import pysbf
import sys
import argparse
from datetime import datetime
import time

# this is the UNIX time (epoch 1/1/1970) of the start of GNSS epoch (1/6/1980)
#GNSSepochInUNIXepoch = 315964819
GNSSepochInUNIXepoch = 315964800
TAIvsUTCin1972 = 10
#leapSecSince1972 = 25
leapSecSince1972 = 16
# one formula is this
#epochDiffNow = GNSSepochInUNIXepoch + TAIvsUTCin1972 - leapSecSinc1972
# but, I can only understand this one, so far, and it seems to match
epochDiffNow = float( GNSSepochInUNIXepoch - 16 )

def getUTCfromGPStime(gpsWN,gpsTOW):
    """ NOT IMPLEMENTED YET

    This is one function in the gpstk library.  It would probably be best to
    use this library or rewrite these algorithms.  But, not now.
    """
    #datetime.datetime result 
    result = 0

    if( gpsWN < 0.0 or gpsTOW > 604800.0 ):
        raise Exception("Invalid GPS Week Number and GPS Time of Week values!")
    pass



def doStuff(f) :
    """
    This function opens the given file, assuming it's a SBF file.
    It extracts the xPPSoffset value from every xPPSOffset block,
    and prints the results with ASCII and UNIX timestamps
    """

    #print('do stuff on file '+f+'...\n')
    with open(f,'r') as sbf_fobj:
      #for blockName, block in pysbf.load(sbf_fobj, blocknames={'xPPSOffset'},limit=10):
      for blockName, block in pysbf.load(sbf_fobj, blocknames={'xPPSOffset'}):
        timeScale=block['Timescale']
        if timeScale == 1:
            # GNSS timestamps on SBF blocks
            #print("DEBUG: SBF block uses GNSS timescale")
            epochDiffNow = float( GNSSepochInUNIXepoch - leapSecSince1972 )
        elif timescale == 2:
            # UTC timestamps on SBF blocks
            #print("DEBUG: SBF block uses UTC timescale")
            epochDiffNow = float( GNSSepochInUNIXepoch )
        else:
            raise Exception('ERROR: SBF block timescale unrecognized: {}'.format(timeScale) )

        WNc=block['WNc']
        TOW=block['TOW']
        offset=block['Offset']
        #print("Week number:{0}; ToW:{1}".format(WNc,TOW))
        s_GPSepoch = float( WNc*60*60*24*7 + float(TOW)/1000 )
        #print(s_GPSepoch)
        #print(epochDiffNow)
        unixtime = int( s_GPSepoch + epochDiffNow )
        dt = datetime.utcfromtimestamp(unixtime)
        iso8601 = datetime.isoformat(dt)
        print("{},{},{}".format(iso8601 , offset, unixtime) )

if __name__ == "__main__" :
    #print('hi\n')
    #print(sys.argv)
    parser = argparse.ArgumentParser(
        description='Prints all xPPSOffset values it finds in given files.'
        ,epilog='''This program reads the files given on the command line.  They
        must be binary SBF formated files.  It locates any and all xPPSOffset
        blocks and prints the ASCII date, xppsoffset, and UNIX time from each
        block.'''
        )
    parser.add_argument('fileList',help='Positional arguments are assumed to be input filenames',nargs='+')
    #parser.add_argument('--outfile',nargs='?',help='output file')
    args = parser.parse_args()
    #print(args.fileList)
    fileList = args.fileList
    #outfile = args.outfile
    #print('working on files:'+str(fileList)+'\n')

    for f in fileList :
        #print('working on file: '+f)
        doStuff(f)

