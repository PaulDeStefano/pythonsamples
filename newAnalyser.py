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
import matplotlib as mpl
import matplotlib.pyplot as plt

# use tex to format text in matplotlib
#rc('text', usetex=True)
mpl.rc('figure'
        ,dpi=100 )
mpl.rc('axes'
        ,grid=True)
mpl.rc('lines'
        ,linestyle=None
        ,marker='+')
mpl.rc('xtick'
        ,direction='out' )
mpl.rc('ytick'
        ,direction='out' )

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
    formatDict = { 'ticFinal'   : 'iso8601 dT ignore ignore' 
            , 'ticFinal.full'   : 'iso8601 dT unixtime nsec' 
            , 'getCorrData'     : 'iso8601,ignore,xPPSOffset,rxClkBias,rx_clk_ns' 
            , 'getCorrData.full': 'iso8601,unixtime,xPPSOffset,rxClkBias,rx_clk_ns' 
            , 'xPPSOffset'      : 'iso8601,xPPSOffset,ignore,ignore,ignore,ignore,ignore,ignore' 
            , 'xPPSOffset.full' : 'iso8601,xPPSOffset,unixtime,ignore,ignore,ignore,ignore,ignore' 
            , 'master'          : 'iso8601,dT,xPPSOffset,rxClkBias,rx_clk_ns,dT_ns,rxClkBias_ns,PPCorr,dTPPCorr' 
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

        parser.add_argument('fileList', nargs='*', help='TIC data files')
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
        parser.add_argument('--loadSaved', nargs='?', default=False, help='Load a previously saved data set from this file')

        self.options = parser.parse_args()
        args = self.options

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
        optionsDict['loadSaved'] = args.loadSaved

        ''' we may not always want to do the same calcuations.  If data has been
        loaded from stored data file, then some processing can be skipped.'''
        optionsDict['reProcess'] = True

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
        db = pandas.merge(
                self.dbDict[loc],dataFrame
                ,how='outer'
                ,left_index=True, right_index=True
                ,copy=True
                )
        self.dbDict[loc] = db
        logMsg('DEBUG: addData...done')
        logMsg(self.dbDict[loc].describe())
        logMsg(self.dbDict[loc])

    #def mergeData(self, dataFrame, loc):
    #    return pandas.merge(self.db,dataFrame,how='inner')

    def decodeFileName(self,s):
        l = s.split(':')
        logMsg('DEBUG: unpacked file spec:',l)
        if len(l) < 2:
            raise Exception('ERROR: file name spec requires >=2 sub-fields; file:location')
        return l

    def loadData(self):
        optionsDict = self.optionsDict
        if self.options.loadSaved :
            self.__loadSaved()
            self.optionsDict['reProcess'] = False
            logMsg("DEBUG: reProcess: ",self.optionsDict['reProcess'])

        logMsg("DEBUG: intputFiles: ",self.optionsDict['inputFiles'])
        if 'inputFiles' in self.optionsDict and self.optionsDict['inputFiles'] != []:
            """ load files at end, assume default format:
            utc dT ...
            """
            ''' inputFiles is a list of files, but may include group identifiers '''
            for s in optionsDict['inputFiles']:
                f,loc,fmt = self.decodeFileName(s)
                #newData = self._loadFile(filename=fileName,fmt = self.formatDict['default'])
                newData = self._loadFile(f,loc,fmt)
                #newData.tz_localize('UTC')
                self.addData(newData, loc=loc)

            if not self.optionsDict['reProcess']:
                '''we already loaded some saved data from, so reverse the flag
                that prevents re-processing the data because more data has been
                added and we should start over'''
                self.optionsDict['reProcess'] = True

        else:
            logMsg("WARNING: no files to load")

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
        logMsg("DEBUG: reProcess: ",self.optionsDict['reProcess'])

    def _getFormat(self,fmt):
        if fmt in self.formatDict:
            return self.formatDict[fmt]
        else:
            return fmt

    def _loadFile(self, filename, loc, fmt='default' ):
        logMsg('NOTICE: _loadFile: loading file:',filename,'...' )
        fmt=self._getFormat(fmt)
        #logMsg('DEBUG: _loadFile: using format:', fmt )

        delim_whitespace = False
        names = None
        if re.search('\s', fmt):
            '''whitespace delimited format'''
            #logMsg('DEBUG: _loadFile: using whitespace as delimiter to read file')
            delim_whitespace=True
            names=fmt.split(' ')
        else:
            #logMsg('DEBUG: _loadFile: using comma as delimiter to read file')
            names=fmt.split(',')

        '''filter ignore columns'''
        usecols = [ name for name in names if name != 'ignore' ]
        #logMsg('DEBUG: _loadFile: names:',names)
        #logMsg('DEBUG: _loadFile: usecols:',usecols)

        newData = pandas.read_csv(filename
                ,index_col=0, parse_dates=True
                ,names=names
                ,delim_whitespace = delim_whitespace
                ,usecols = usecols
                ,nrows = self.optionsDict['importLimit']
                ,comment = '#'
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
        for loc in self.dbDict.keys():
            dat = self.dbDict[loc]
            if dat.empty:
                logMsg("DEBUG: empty data for location:",loc,"skipping")
                continue
            logMsg('DEBUG: preview: loc=',loc,'\n', dat.describe() )
            #logMsg('DEBUG: preview: loc=',loc,'\n', self.dbDict[loc].head() )
            previewDF = dat
            print previewDF.head(10)
            print previewDF.tail(10)
            previewDF.plot(title=loc+':'+self.options.desc)
            plt.show()

        logMsg('DEBUG: previewing...done')

    def prep(self):
        '''fix up stuff before other calculations'''
        '''dT is in seconds, but we're interested in nanosecond level differences.
        And, besides, it will be easiest to convert to a common unit.'''
        if not self.optionsDict['reProcess'] :
            ''' skip this stuff'''
            return None

        for loc in self.dbDict.keys():
            dat = self.dbDict[loc]
            if dat.empty:
                logMsg("DEBUG: empty data for location:",loc,"skipping")
                continue
            dat = self.dbDict[loc]
            '''convert dT to ns'''
            if 'dT' in dat.keys():
                '''drop meas > 1s'''
                df = dat['dT']
                df = df[df < 1.01]
                dat['dT'] = df
                '''convert to ns'''
                df = df * 1E9
                dat['dT_ns'] = df

            '''convert rxClkBias to ns'''
            if 'rxClkBias' in dat.keys():
                dat['rxClkBias_ns'] = dat['rxClkBias'] * 1E6

    def doXPPScorr(self):
        logMsg("DEBUG: reProcess: ",self.optionsDict['reProcess'])
        if not self.optionsDict['reProcess'] :
            return None

        logMsg('DEBUG: xPPScorr...')
# apply xppsoffset
        for loc in self.dbDict.keys():
            dat = self.dbDict[loc]
            if dat.empty:
                logMsg("DEBUG: empty data for location:",loc,"skipping")
                continue
            if ('dT_ns' not in dat.keys()) or ('xPPSOffset' not in dat.keys()):
                raise Exception("Data needed for xPPSOffset corrections not found")
            coeff = -1
            if not self.options.negOffset:
                coeff = 1
            dat['dTCorr'] = dat.dT_ns + coeff * dat.xPPSOffset 
            dat[['dT_ns','dTCorr']].plot(title=loc+':'+self.options.desc,grid=True)
            plt.show()
        logMsg('DEBUG: xPPScorr...done')

    def doPPPcorr(self):
# find PPP Correction & apply
        if not self.optionsDict['reProcess'] :
            return None

        logMsg('DEBUG: PPCorr...')
        for loc in self.dbDict.keys():
            dat = self.dbDict[loc]
            if dat.empty:
                logMsg("DEBUG: empty data for location:",loc,"skipping")
                continue
            if ('rxClkBias_ns' not in dat.keys()) or ('rx_clk_ns' not in dat.keys()):
                raise Exception("Data needed for PP corrections not found")
            logMsg("DEBUG: loc:",loc,":",dat)
            dat['PPCorr'] = dat.rxClkBias_ns - dat.rx_clk_ns
            dat['dTPPCorr'] = dat.dTCorr - dat.PPCorr
            dat[['dT_ns','PPCorr','dTPPCorr']].plot(title=loc+':'+self.options.desc)
            plt.show()
        logMsg('DEBUG: PPCorr...done')

    def save(self):
        logMsg('DEBUG: saving database to file...')
        fileName = self.options.outputPrefix
        if fileName:
            logMsg("DEBUG: saving to HDF5 store in file",fileName)
        #with pandas.HDFStore(fileName+'.hdf5') as store:
            store = pandas.HDFStore(fileName+'.hdf5')
            for loc in self.dbDict.keys():
                store[loc] = self.dbDict[loc]
            store.close()
            del store
        else:
            logMsg("DEBUG: couldn't write, no outputFile specified")

    def __loadSaved(self):
        logMsg('DEBUG: loaded saved database from file...')
        fileName = self.options.loadSaved
        if fileName:
            logMsg("DEBUG: loading saved data from HDF5 store in file",fileName)
            store = pandas.HDFStore(fileName)
        #with pandas.HDFStore(fileName) as store:
            for loc in self.dbDict.keys():
                storeKey = '/'+loc
                logMsg("DEBUG: loading key",storeKey,"from HDF5 store into location",loc)
                self.dbDict[loc] = store[storeKey]

            store.close()
        else:
            logMsg("DEBUG: couldn't load, no loadSaved file specified")

    def analyse(self):
        logMsg('DEBUG: Analyse...')
        for loc in self.dbDict.keys():
            dat = self.dbDict[loc]
            dat = dat.dropna(how='any')
            logMsg("DEBUG: after dropna:",dat)
        logMsg('DEBUG: Analyse...done')

## MAIN ##
def runMain():
    tof = tofAnalayser()
    tof.configure()
    #tof.configure(sys.argv[1:])
# import main data
    tof.loadData()
# preview
    #tof.preview()
# organize data
    tof.prep()
    #tof.preview()
# import correcitions
# apply corrections
    tof.doXPPScorr()
    #tof.preview()
    tof.doPPPcorr()
    #tof.preview()
# store analysed data
    tof.save()
# analyse data
    tof.analyse()
    tof.preview()
# store analysed data
    tof.save()
# overview plot
# find sub-series
# reanalyse
# replot


if __name__ == "__main__" :
    try:
        runMain()
    except KeyboardInterrupt as e:
        '''relax, exit but supress traceback'''
