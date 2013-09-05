#!/usr/bin/python2.7
""" newAnalyser.py
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
import argparse
import sys
import pandas
import re
import matplotlib.pyplot as plt

def logMsg(s, *args):
    #print("DEBUG: logMsg called")
    if args:
        for a in args:
            s += (" "+str(a))
    print >> sys.stderr , str(s)
    #print(str(s),file=sys.stderr) # python3


class tofAnalayser:
    """Draft Implimentation of TOF Data Analyser Module"""
    release = releaseName = '2013.09.01'
    formatDict = { 'ticFinal' : 'iso8601 dT ignore ignore' 
            , 'ticFinal.full' : 'iso8601 dT unixtime nsec' 
            , 'getCorrData' : 'iso8601,xPPSOffset,rxClkBias,rx_clk_ns' 
            , 'getCorrData' : 'iso8601,xPPSOffset,rxClkBias,rx_clk_ns' 
            , 'xPPSOffset.dat' : 'iso8601,xPPSOffset,unixtime,ignore,ignore,ignore,ignore,ignore' 
            , 'xPPSOffset.dat.full' : 'iso8601,xPPSOffset,unixtime,ignore,ignore,ignore,ignore,ignore' 
            , 'master' : 'iso8601,dT,xPPSOffset,rxClkBias,rx_clk_ns' 
            }
    formatDict['default'] = formatDict['ticFinal']
    optionsDict = {}
    masterDF = pandas.DataFrame({
        'iso8601'       : []
        ,'dT'           : []
        ,'xPPSOffset'   : []
        ,'rxClkBias'    : []
        ,'rx_clk_ns'    : []
        })

    dbDict = { 'nu1' : pandas.DataFrame()
            , 'nd280' : pandas.DataFrame()
            , 'sk' : pandas.DataFrame()
            }

    def __init__(self, argv=None):
        if argv:
            self.configure(argv)

    def configure(self, argv=None ):
        logMsg("DEBUG: arvg:",argv)
        self.parser = argparse.ArgumentParser(description='New TIC data plotter and analyser.')
        parser = self.parser

        parser.add_argument('fileList', nargs='+', help='TIC data files')
        parser.add_argument('--desc', nargs='?', help='Description (title) for plots', default='DEFAULT DESCRIPTION')
        parser.add_argument('-g', '--gap', nargs='?', default='3', help='Maximum gap/tolerance (s) between epochs')
        parser.add_argument('--offsets', nargs='?', help='File continating xPPSoffset values (from sbf2offset.py)')
        parser.add_argument('--addOffset', dest='negOffset', action='store_false', default=True, help='Boolean.  Add offset values to TIC measurements (dT)')
        parser.add_argument('--subtractOffset', dest='negOffset', action='store_true', default=True, help='Boolean. Subtract offset values from TIC measurements (dT)')
        parser.add_argument('--histbins', nargs='?', default=50, help='Number of bins in histograms')
        parser.add_argument('--shiftOffset', '-s', nargs='?', default=0.0, help='shift time of xPPSOffset corrections wrt. TIC measurements by this many seconds')
        parser.add_argument('--importLimit', '-L', nargs='?', default=100000000, help='limit imported data to the first <limit> lines')
        parser.add_argument('--outputPrefix', nargs='?', default=False, help='Save the results of the applised xPPSOffset corrections to a series of files with this name prefix')
        parser.add_argument('--frequency', '-F', action='store_true',default=False, help='Calculate Frequency Departure of all time series analysed')
        parser.add_argument('--fft', '-S', action='store_true',default=False, help='Calculate Spectral Density (Fourier Transform) of any time series')
        parser.add_argument('--corr', '-C', nargs='?', help='File continating "correction" values (from getCorrData.sh)')
        parser.add_argument('--showFormats', action='store_true', default=False, help='Show a list of known formats')

        self.args = parser.parse_args()
        args = self.args

        optionsDict = self.optionsDict
        optionsDict['inputFiles'] = args.fileList
        optionsDict['description'] = args.desc
        optionsDict['maxEpochGap'] = float(args.gap)
        optionsDict['offsetFile'] = args.offsets
        optionsDict['negOffset'] = args.negOffset
        optionsDict['numBins'] = int(args.histbins)
        optionsDict['shiftOffset'] = float(args.shiftOffset)
        optionsDict['importLimit'] = int(args.importLimit)
        optionsDict['storeFilePrefix'] = args.outputPrefix
        optionsDict['doFreq'] = args.frequency
        optionsDict['doFT'] = args.fft
        optionsDict['corr'] = args.offsets
        optionsDict['showFormats'] = args.showFormats

        logMsg('DEBUG: harvested coniguration:',optionsDict)

        if args.showFormats:
            for fmt in self.formatDict:
                print(fmt)

#print("DEBUG: negOffset:" + str(negOffset) )

    def addData(self, dataFrame, loc):
        logMsg('DEBUG: addData...')
        logMsg('DEBUG: addData: dataFrame:\n',dataFrame.describe())
        if None == loc:
            raise Exception('ERROR: addData: cannot work with loc=None')
        db = self.dbDict[loc].append(dataFrame)
        self.dbDict[loc] = db
        logMsg('DEBUG: addData...done')
        logMsg(self.dbDict[loc].describe())

    def mergeData(self, dataFrame, loc):
        pandas.merge(self.db,dataFrame,how='inner')

    def decodeFileName(self,s):
        l = s.split(':')
        logMsg('DEBUG: unpacked file spec:',l)
        if len(l) < 2:
            raise Exception('ERROR: file name spec requires >=2 sub-fields; file:location')
        return l

    def loadData(self):
        optionsDict = self.optionsDict
        if 'inputFiles' in self.optionsDict:
            """ load files at end, assume default format:
            utc dT ...
            """
            ''' inputFiles is a list of files, but may include group identifiers '''
            for s in optionsDict['inputFiles']:
                f,loc,fmt = self.decodeFileName(s)
                #newData = self._loadFile(filename=fileName,fmt = self.formatDict['default'])
                newData = self._loadFile(f,loc,fmt)
                #newData.tz_localize('UTC')
                newData = self.cleanUpData(newData)
                self.addData(newData, loc=loc)

        else:
            logMsg("ERROR: no files to load")
            return 1

        """
        if 'offsetFile' in self.optionsDict :
            for s in self.optionsDict['offsetFile'] :
                loc, fileName, fmt = s.split(':')
                newData = self._loadFile(fileName,fmt='xPPSOffset.dat')
        if 'corr' in self.optionsDict :
            for s in self.optionsDict['corr'] :
                loc, fileName, fmt = s.split(':')
                newData = self._loadFile(fileName,fmt='getCorrData')
        """

    def _getFormat(self,fmt):
        if fmt in self.formatDict:
            return self.formatDict[fmt]
        else:
            return fmt

    def _loadFile(self, filename, loc, fmt='default' ):
        logMsg('NOTICE: _loadFile: loading file:',filename,'...' )
        fmt=self._getFormat(fmt)
        logMsg('DEBUG: _loadFile: using format:', fmt )

        delim_whitespace = False
        names = None
        if re.search('\s', fmt):
            '''whitespace delimited format'''
            logMsg('DEBUG: _loadFile: using whitespace as delimiter to read file')
            delim_whitespace=True
            names=fmt.split(' ')
        else:
            logMsg('DEBUG: _loadFile: using comma as delimiter to read file')
            names=fmt.split(',')

        '''filter ignore columns'''
        usecols = [ name for name in names if name != 'ignore' ]
        logMsg('DEBUG: _loadFile: names:',names)
        logMsg('DEBUG: _loadFile: usecols:',usecols)

        newData = pandas.read_csv(filename
                ,index_col=0, parse_dates=True
                ,names=names
                ,delim_whitespace = delim_whitespace
                ,usecols = usecols
                ,nrows = self.optionsDict['importLimit']
                )

        logMsg('DEBUG: _loadFile: loading file...done.')
        logMsg(newData.head())
        if True == newData.empty:
            logMsg('ERROR: _loadFile: load failed on file',filename)
            raise Exception('ERROR: load of file {} failed for unknown reason'.format(filename) )
        return newData

    def preview(self):
        logMsg('DEBUG: previewing...')
        logMsg('DEBUG: ', self.dbDict.keys() )
        for key in self.dbDict.keys():
            logMsg('DEBUG: preview: loc=',key,'\n', self.dbDict[key].describe() )
            #logMsg('DEBUG: preview: loc=',key,'\n', self.dbDict[key].head() )
            previewDF = self.dbDict[key]
            previewDF = previewDF['dT'].head(1000)
            plt.show()


        logMsg('DEBUG: previewing...done')

## MAIN ##
def runMain():
    tof = tofAnalayser()
    tof.configure()
    #tof.configure(sys.argv[1:])
# import main data
    tof.loadData()
# preview
    tof.preview()
# import correcitions
# organize data
# apply corrections
# analyse data
# overview plot
# store analysed data
# find sub-series
# reanalyse
# replot


# use tex to format text in matplolib
#rc('text', usetex=True)

if __name__ == "__main__" :
    runMain()
