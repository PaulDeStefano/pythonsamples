#!/usr/local/bin/python2.7
""" sbf2offset.py
    Reads SBF binary data files and produces plain text file
    containing PVTGeoblock data

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
import pysbf
import argparse
from datetime import datetime
from sys import stderr

# this is the UNIX time (epoch 1/1/1970) of the start of GNSS epoch (1/6/1980)
#GNSSepochInUNIXepoch = 315964819
GNSSepochInUNIXepoch = 315964800
TAIvsUTCin1972 = 10
#leapSecSince1972 = 25
leapSecSince1972 = 16
# one formula is this
#epochDiffNow = GNSSepochInUNIXepoch + TAIvsUTCin1972 - leapSecSince1972
# but, I can only understand this one, so far, and it seems to match
epochDiffNow = float(GNSSepochInUNIXepoch - 16)

class t2kSBFDataError(Exception):
    """ exception class to raise errors in SBF data """
    pass

class t2kSeptPVTTime:
    """Helps convert GNSS time to other times
    """

    def __init__(self, WNc=None, TOW=None, timeSystem=None):
        if timeSystem == None:
            raise Exception("ERROR: init of class t2kSeptPVTTime requires three parameters")

        if timeSystem == 0:
            # GNSS timestamps on SBF blocks
            #print("DEBUG: SBF block uses GNSS timeSystem")
            epochDiffNow = float( GNSSepochInUNIXepoch - leapSecSince1972 )
        elif timeSystem == 1:
            # Galileo timestamps on SBF blocks
            #print("DEBUG: SBF block uses UTC timeSystem")
            raise Exception("ERROR: SBF block uses GLONASS time, not yet implimented.")
        elif timeSystem == 255 :
            # GLONASS timestamps on SBF blocks
            raise t2kSBFDataError("ERROR: SBF block has error code for TimeSystem value: 255")
        else:
            raise t2kSBFDataError("ERROR: SBF timeSystem unrecognized: {}".format(timeSystem) )

        self.error = 0
        self.WNc=WNc
        self.TOW=TOW
        #print("Week number:{0}; ToW:{1}".format(WNc,TOW))
        secIntoYr = self.WNc*60*60*24*7
        secIntoWk = float(self.TOW)/1000
        self.s_GPSepoch = float( secIntoYr + secIntoWk )
        #print(s_GPSepoch)
        #print(epochDiffNow)
        self.unixtime = float( self.s_GPSepoch + epochDiffNow )
        self.dt = datetime.utcfromtimestamp(self.unixtime)

    def getTuple(self):
        """Returns useful bits
        """
        iso8601 = datetime.isoformat(self.dt)
        dayOfYear = datetime.utctimetuple(self.dt).tm_yday
        unixDays = float(self.unixtime)/86400
        # Juliain date, 2456401.5=JD of unix epoch
        jd = unixDays + 2440587.5
        # Modified Juliain date, JD - 2400000.5
        mjd = jd - 2400000.5
        return (iso8601, self.unixtime, self.WNc, self.TOW, jd, mjd, dayOfYear)

def doStuff(f) :
    """
    This function opens the given file, assuming it's a SBF file.
    It extracts the PVTGeodetic values from every PVTGeo block,
    and prints the results with ASCII and UNIX timestamps
    """

    #print('do stuff on file '+f+'...\n')
    with open(f,'r') as sbf_fobj:
      #for blockName, block in pysbf.load(sbf_fobj, blocknames={'xPPSOffset'},limit=10):
      for blockName, block in pysbf.load(sbf_fobj, blocknames={'PVTGeodetic_v2'}):
        errCode=block['Error']
        phi=block['Phi']
        lmbd=block['Lambda']
        h=block['h']
        rxClkBias=block['RxClkBias']
        rxClkDrift=block['RxClkDrift']
        nrSV=block['NrSV']
        mode=block['Mode']
        signalInfo=block['SignalInfo']
        alertFlag=block['AlertFlag']
        WNc=block['WNc']
        TOW=block['TOW']
        timeSystem=block['TimeSystem']
        try:
            if (errCode > 0):
                raise t2kSBFDataError('WARNING: Unknown block error code: {}'.format(errCode))
            rcvrTime = t2kSeptPVTTime(WNc,TOW,timeSystem)
        except t2kSBFDataError as e:
            stderr.write(str(e)+', skipping block (WNc={},TOW={},NrSV={},SignalInfo={},AlertFlag={})'.format(errCode,WNc,TOW,nrSV,signalInfo,alertFlag )+'\n')
            continue
        iso8601, unixtime, WNc, TOW, jd, mjd, dayOfYear = rcvrTime.getTuple()
        print("{},{},{},{},{},{},{},{},{},{},{},{},{},{},{},{},{}".format(
                iso8601, unixtime,
                errCode,
                phi, lmbd, h,
                rxClkBias, rxClkDrift,
                nrSV,
                WNc, TOW, jd, mjd, dayOfYear,
                mode, signalInfo, alertFlag ) )

if __name__ == "__main__" :
    #print('hi\n')
    #print(sys.argv)
    parser = argparse.ArgumentParser(
            formatter_class=argparse.RawDescriptionHelpFormatter
            ,description='Prints all PVTGeo values it finds in given files.'
            ,epilog='''
This program reads the files given on the command line.  They must be binary
SBF formated files.  It locates any and all PVTGeo blocks and prints the
ISO8601 date, and UNIX time, & other data from each block.

output format:
<isoDate>,<UNIXtime>,<SBF blk errCode>,<phi>,<lambda>,<height>,<rxClkBias>,<rxClkDrift>,<# Satellites in PVT>,<WNc>,<TOW>,<JulianDay>,<MJD>,<dayOfYear>,Mode,SignalInfo,AlertFlag

For validation purposes, the output data also includes the GNSS Week Number
(WNc) and Time of Week (TOW).

WNc = number of weeks since GNSS epoch time (Jan 1 1980)
TOW = number of miliseconds since start of the current week
phi = Phi angle measurement, Geodetic coordinates
lmbd = Lambda angle measurement, Geodetic coordinates
h = height above Geodetic datum surface 
RxClkBias = Measured time difference (ns) between internal clock (and external Freq Source) and Time System Time
RxClkDrift = Calculated error in frequncy of internal clock (and ext. FS)
# of Satellites in PVT
'''
            )
    parser.add_argument('fileList',help='Positional arguments are assumed to be input filenames',nargs='+')
    #parser.add_argument('--outfile',nargs='?',help='output file')
    parser.add_argument('--header',action='store_true',default=True,help='produce column description strings as first line of output (default)')
    parser.add_argument('--noheader',dest='header',action='store_false',default=True,help='omit header at beginning of output')
    args = parser.parse_args()
    #print(args.fileList)
    fileList = args.fileList
    header = args.header
    #outfile = args.outfile
    #print('working on files:'+str(fileList)+'\n')

    if (header):
        print 'ISO_Date,UNIX_time,SBFblkErrCode,phi,lambda,height,rxClkBias,rxClkDrift,nrSV,WNc,TOW,julianDay,modifiedJulianDay,dayOfYear,Mode,SignalInfo,AlertFlag'
    for f in fileList :
        #print('working on file: '+f)
        doStuff(f)

