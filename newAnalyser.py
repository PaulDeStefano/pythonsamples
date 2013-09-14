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
import copy
import matplotlib.dates as mdates
from matplotlib.ticker import AutoMinorLocator
import numpy as np

# use tex to format text in matplotlib
#rc('text', usetex=True)
mpl.rcParams['figure.figsize'] = (14,9)
mpl.rcParams['figure.facecolor'] = '0.75'
mpl.rcParams['figure.dpi'] = 100
#mpl.rcParams['figure.subplot.left'] = 0.06
mpl.rcParams['figure.subplot.left'] = 0.07
mpl.rcParams['figure.subplot.bottom'] = 0.08
mpl.rcParams['figure.subplot.right'] = 0.96
mpl.rcParams['figure.subplot.top'] = 0.96 
mpl.rcParams['grid.alpha'] = 0.5
mpl.rcParams['axes.grid'] = True
mpl.rcParams['axes.facecolor'] = '0.90'
mpl.rc('lines'
        ,linestyle=None
        ,marker='+'
        ,markersize=3
        ,antialiased=True
        )
mpl.rc('font'
        ,size=9 )
mpl.rc('legend'
        ,markerscale=2.0
        ,fontsize='small')
mpl.rc('text'
        ,usetex=False )
mpl.rc('xtick'
        ,labelsize='medium'
        ,direction='out' )
mpl.rc('ytick'
        ,labelsize='medium'
        ,direction='out' )

# disable sparse x ticks, doesn't work
pandas.plot_params['x_compat'] = True

def logMsg(s, *args):
    #print("DEBUG: logMsg called")
    if args:
        for a in args:
            s += (" "+str(a))
    print >> sys.stderr , str(s)
    #print(str(s),file=sys.stderr) # python3

def headtail(dataFrame):
    '''wraper for previews of dataframes'''
    h = dataFrame.head(2)
    t = dataFrame.tail(2)
    return str(h)+str(t)

class tofAnalayser:
    """Draft Implimentation of TOF Data Analyser Module"""
    release = releaseName = '2013.09.01'
    formatDict = { 'ticFinal'   : 'iso8601 dT ignore ignore' 
            , 'ticFinal.full'   : 'iso8601 dT unixtime nsec' 
            , 'ticOrig'         : 'utcDate,utcTime,dT,ignore' 
            , 'ticOrig.full'    : 'utcDate,utcTime,dT,unixtime' 
            , 'ticOrigMod'      : 'iso8601,dT,ignore' 
            , 'ticOrigMod.full' : 'iso8601,dT,unixtime' 
            , 'getCorrData'     : 'iso8601,ignore,xPPSOffset,rxClkBias,rx_clk_ns' 
            , 'getCorrData.full': 'iso8601,unixtime,xPPSOffset,rxClkBias,rx_clk_ns' 
            , 'xPPSOffset'      : 'iso8601,xPPSOffset,ignore,ignore,ignore,ignore,ignore,ignore' 
            , 'xPPSOffset.full' : 'iso8601,xPPSOffset,unixtime,ignore,ignore,ignore,ignore,ignore' 
            , 'master'          : 'iso8601,dT,xPPSOffset,rxClkBias,rx_clk_ns,dT_ns,rxClkBias_ns,PPCorr,dTPPCorr,dTCorr_avg,dTPPCorr_avg' 
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

    colorMap =  {
                'dT' : 'red'
                ,'dT_ns' : 'darkred'
                ,'dTCorr' : 'lightgreen'
                ,'xPPSOffset': 'grey'
                ,'rxClkBias': 'lightblue'
                ,'rxClkBias_ns': 'blue'
                ,'rx_clk_ns': 'magenta'
                ,'PPCorr' : 'yellow'
                ,'dTPPCorr' : 'cyan'
                ,'dT-StnClkOff' : 'orange'
                ,'dTCorr_avg' : 'lightgreen'
                ,'dTPPCorr_avg' : 'cyan'
                }
    markerMap =  {
                'dT' : 'x'
                ,'dT_ns' : '+'
                ,'dTCorr' : '+'
                ,'xPPSOffset': '+'
                ,'rxClkBias': '+'
                ,'rxClkBias_ns': '+'
                ,'rx_clk_ns': '+'
                ,'PPCorr' : '+'
                ,'dTPPCorr' : '+'
                ,'dT-StnClkOff' : '+'
                ,'dTCorr_avg' : 'o'
                ,'dTPPCorr_avg' : 'o'
                }
    styleMap =  {
                'dT' : 'rx'
                ,'dT_ns' : 'r+'
                ,'dTCorr' : 'g+'
                ,'xPPSOffset': 'k+'
                ,'rxClkBias': 'bx'
                ,'rxClkBias_ns': 'b+'
                ,'rx_clk_ns': 'm+'
                ,'PPCorr' : 'y+'
                ,'dTPPCorr' : 'c+'
                ,'dT-StnClkOff' : 'o+'
                }

    dateFormatter = mdates.DateFormatter('%Y%m%d %H:%M:%S')
    xDataDateFormatter = mdates.DateFormatter('%a %d %b #%j %H:%M:%S')
    majorTickFormater = mdates.DateFormatter('%d %b #%j\n%H:%M')

    def locations(self):
        return self.dbDict.keys()

    def __init__(self, argv=None):
        if argv:
            self.configure(argv)

    def configure(self, argv=None ):
        logMsg("DEBUG: argv:",argv)
        self.parser = argparse.ArgumentParser(description='New TIC data plotter and analyser.')
        parser = self.parser

        parser.add_argument('fileList', nargs='*', help='TIC data files')
        parser.add_argument('--desc', nargs='?', help='Description (title) for plots', default='DEFAULT DESCRIPTION')
        parser.add_argument('-g', '--gap', nargs='?', default='3', help='Maximum gap/tolerance (s) between epochs')
        parser.add_argument('--offsets', nargs='?', help='File continating xPPSoffset values (from sbf2offset.py)')
        parser.add_argument('--addOffset', dest='negOffset', action='store_false', default=True, help='Boolean.  Add offset values to TIC measurements (dT)')
        parser.add_argument('--subtractOffset', dest='negOffset', action='store_true', default=True, help='Boolean. Subtract offset values from TIC measurements (dT)')
        parser.add_argument('--histbins', nargs='?', default=50, help='Number of bins in histograms')
        parser.add_argument('--shiftOffset', '-s', nargs='?', default=0, help='shift time of xPPSOffset corrections wrt. TIC measurements by this many seconds')
        parser.add_argument('--importLimit', '-L', nargs='?', default=100000000, help='limit imported data to the first <limit> lines')
        parser.add_argument('--outputPrefix', nargs='?', default=False, help='Save the results of the applied xPPSOffset corrections to a series of files with this name prefix')
        parser.add_argument('--frequency', '-F', action='store_true',default=False, help='Calculate Frequency Departure of all time series analysed')
        parser.add_argument('--fft', '-S', action='store_true',default=False, help='Calculate Spectral Density (Fourier Transform) of any time series')
        parser.add_argument('--corr', '-C', nargs='?', help='File continating "correction" values (from getCorrData.sh)')
        parser.add_argument('--showFormats', action='store_true', default=False, help='Show a list of known formats')
        parser.add_argument('--loadSaved', nargs='?', default=False, help='Load a previously saved data set from this file')
        parser.add_argument('--forceReProcess', action='store_true', default=False, help='Froce reprocessing of data loaded from saved data files')
        parser.add_argument('--hdf5', action='store_true', default=True, help='Use HDF5 file format to store data')
        parser.add_argument('--csv', action='store_true', default=False, help='Use CSV file format to store data TODO: NOT IMPLIMENTED YET')
        parser.add_argument('--debug', action='store_true', default=False, help='Use CSV file format to store data TODO: NOT IMPLIMENTED YET')
        parser.add_argument('--avgWindow', nargs='?', default=10000, help='Calculate rolling average (of selected data) with specified window size (in units of samples, i.e. secs)' )
        parser.add_argument('--resamplePlot', nargs='?', default=10000/4, help='Select sub-sample size for plotting selected data types (averaging types). Default=1/4 of avgWindow => 4 plot points in each window' )
        parser.add_argument('--previewPercent', nargs='?', default=20, help='Sub-sample size for all *preview* plotting' )
        parser.add_argument('--storeOnly', action='store_true', default=False, help='after loading data, save it (if outputFile given), and quit.  Useful for consolidating data into HDF file, faster reading later')

        self.options = parser.parse_args()
        args = self.options

        optionsDict = self.optionsDict
        optionsDict['inputFiles'] = args.fileList
        optionsDict['description'] = args.desc
        optionsDict['maxEpochGap'] = float(args.gap)
        optionsDict['offsetFile'] = args.offsets
        optionsDict['negOffset'] = args.negOffset
        optionsDict['numBins'] = int(args.histbins)
        optionsDict['shiftOffset'] = args.shiftOffset
        optionsDict['importLimit'] = int(args.importLimit)
        optionsDict['storeFilePrefix'] = args.outputPrefix
        optionsDict['doFreq'] = args.frequency
        optionsDict['doFT'] = args.fft
        optionsDict['corr'] = args.offsets
        optionsDict['showFormats'] = args.showFormats
        optionsDict['loadSaved'] = args.loadSaved
        optionsDict['forceReProcess'] = args.forceReProcess
        optionsDict['debug'] = args.debug
        optionsDict['avgWindow'] = int(args.avgWindow)
        if args.resamplePlot == None:
            optionsDict['resamplePlot'] = str(int(np.floor(optionsDict['avgWindow'] / 5)))+'S'
        else:
            optionsDict['resamplePlot'] = str(int(args.resamplePlot))+'S'
        optionsDict['previewPercent'] = int(args.previewPercent)
        optionsDict['storeOnly'] = args.storeOnly

        ''' we may not always want to do the same calcuations.  If data has been
        loaded from stored data file, then some processing can be skipped.'''
        optionsDict['reProcess'] = True
        '''configure reusable color and style attributes for TOF data types'''
        optionsDict['colorMap'] = self.colorMap
        optionsDict['styleMap'] = self.styleMap
        optionsDict['tofPlotPref'] = {
                'color:sk'      : copy.copy(self.colorMap)
                ,'color:nd280'  : copy.copy(self.colorMap)
                ,'color:nu1'    : copy.copy(self.colorMap)
                ,'marker:sk'     : copy.copy(self.markerMap)
                ,'marker:nd280'  : copy.copy(self.markerMap)
                ,'marker:nu1'    : copy.copy(self.markerMap)
                }
        optionsDict['tofPlotPref']['color:sk']['dT_ns']     = 'red'
        optionsDict['tofPlotPref']['color:nd280']['dT']     = 'red'
        optionsDict['tofPlotPref']['marker:sk']['dT']        = 'x'
        optionsDict['tofPlotPref']['marker:nd280']['dT_ns']  = 'x'

        '''allow different shift values per location'''
        self.parseDictOption( 'shiftMap',self.options.shiftOffset,delim2='=' )

        '''When plotting, resample these datatypes only'''
        masterFromatList = self.formatDict['master']
        logMsg("DEBUG: configure: master formats:",masterFromatList )
        resampleList = filter( lambda x: re.search('_avg', x) ,masterFromatList.split(',') )
        logMsg("DEBUG: configure: resampleList:", resampleList )
        optionsDict['resampleDataBeforePlotList'] = filter( lambda x: re.search('_avg', x) , resampleList )

        logMsg('DEBUG: harvested coniguration:',optionsDict)

        if args.showFormats:
            for fmt in self.formatDict:
                print(fmt)

#print("DEBUG: negOffset:" + str(negOffset) )

    def parseDictOption( self,key,s,delim2=':',cast=lambda x: int(x) ):
        self.optionsDict[key] = self.strToDict(s,delim2=delim2,cast=cast)

    def strToDict(self,s,default=0,delim1=',',delim2=':',cast=lambda x: int(x) ):
        logMsg("DEBUG: strToDict ...")
        #logMsg("DEBUG: strToDict: got s:",s)
        if type(s) == type(int()) :
            logMsg("DEBUG: strToDict: value is number, not string, can't unpack, appling as default")
            default = s
            s = 'all='+str(default)
        groups = s.split(delim1)
        d = {}
        for loc in self.locations():
            v = default
            for name,val in [x.split(delim2) for x in groups ]:
                #logMsg( 'DEBUG: loc:',loc,' name:',name,' val:',val )
                if (loc == name) or (loc == 'all') :
                    v = cast(val)
            d[loc] = v
        logMsg("DEBUG: strToDict ...done")
        return d

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
            if not self.options.forceReProcess:
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

    def _getFormat(self,fmt):
        if fmt in self.formatDict.keys() :
            return self.formatDict[fmt]
        elif re.search(fmt,self.formatDict['master']) :
            '''okay, at least this one could be meaningful'''
            return fmt
        else :
            raise Exception("DEBUG: couldn't interpret format specification: "+fmt)

    def _loadFile(self, filename, loc, fmt='default' ):
        logMsg('NOTICE: _loadFile: loading file:',filename,'...' )
        fmt=self._getFormat(fmt)
        logMsg('DEBUG: _loadFile: using format:', fmt )

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
        logMsg('DEBUG: _loadFile: names:',names)
        logMsg('DEBUG: _loadFile: usecols:',usecols)

        newData = pandas.read_csv(filename
                ,index_col=0, parse_dates=True
                ,names=names
                ,delim_whitespace = delim_whitespace
                ,usecols = usecols
                ,nrows = self.optionsDict['importLimit']
                ,header=0
                ,skiprows=1
#                ,comment = '#' # not supported in v0.10!!
                )

        logMsg('DEBUG: _loadFile: loading file...done.')
        logMsg(newData.head())
        if True == newData.empty:
            logMsg('ERROR: _loadFile: load failed on file',filename)
            raise Exception('ERROR: load of file {} failed for unknown reason'.format(filename) )
        return newData

    def __previewDF(self,previewDF, title=None,debug=False, **kwargs):
        if debug and not self.options.debug:
            return
        logMsg("DEBUG: previewDF ...")
        if None == title:
            title=self.options.desc
        print previewDF.head(2)
        print previewDF.tail(2)
        #previewDF.plot(grid=True,title='Preview:'+title)
        #for key in previewDF.keys():
        #    previewDF[key].plot(style=self.styleMap[key])
        keys = previewDF.keys()
        if len(keys) > 1 :
            useSub=True
        else:
            useSub=False
        ppct = self.optionsDict['previewPercent']
        resampleStr = str(int(np.floor( 100/ppct ) ))+'S'
        previewDF.resample(resampleStr).plot(subplots=useSub,grid=True)
        plt.suptitle('Preview:'+title+'(downsampled)')
        plt.show()
        logMsg("DEBUG: previewDF ...done")

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
            self.__previewDF(dat,title=loc)

        logMsg('DEBUG: previewing...done')

    def prep(self):
        '''fix up stuff before other calculations'''
        '''dT is in seconds, but we're interested in nanosecond level differences.
        And, besides, it will be easiest to convert to a common unit.'''
        if not self.optionsDict['reProcess'] :
            ''' skip this stuff'''
            logMsg("DEBUG: prep: reprocessing disabled, skipping")
            return None

        '''drop NAN since we are sure we are going to re calculate
        If not done here, should include condition on reprocessing.
        shold be first thing after loadFile'''
        self.__dropNAN()

        for loc in self.dbDict.keys():
            dat = self.dbDict[loc]
            if dat.empty:
                logMsg("DEBUG: empty data for location:",loc,"skipping")
                continue

            dat = self.dbDict[loc]

            '''sort'''
            #dat = dat.sort_index()

            '''convert dT to ns'''
            logMsg("DEBUG: trying to convert dT (s) to dT (ns), loc:",loc)
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

            assert( dat is self.dbDict[loc] )

    def doXPPScorr(self):
        logMsg("DEBUG: reProcess: ",self.optionsDict['reProcess'])
        if not self.optionsDict['reProcess'] :
            logMsg("DEBUG: doXPPScorr: reprocessing disabled, skipping")
            return None

        logMsg('DEBUG: xPPScorr...')
# apply xppsoffset
        for loc in self.dbDict.keys():
            dat = self.dbDict[loc]
            if dat.empty:
                logMsg("DEBUG: empty data for location:",loc,"skipping")
                continue
            if ('dT_ns' not in dat.keys()) or ('xPPSOffset' not in dat.keys()):
                #raise Exception("Data needed for xPPSOffset corrections not found")
                logMsg("WARNING: insufficient data for xPPSoffset correction, loc:",loc,", skipping")
                continue
            coeff = -1
            if not self.options.negOffset:
                coeff = 1
            shiftVal = self.optionsDict['shiftMap'][loc]
            logMsg("DEBUG: using shift value:",shiftVal)
            dat['dTCorr'] = dat.dT_ns.shift(shiftVal) + coeff * dat.xPPSOffset 
            #dat[['dT_ns','dTCorr','xPPSOffset']].plot(title=loc+':'+self.options.desc,grid=True)
            #plt.show()
            self.__previewDF( dat[['dT_ns','dTCorr','xPPSOffset']] ,title='xPPSOffset:'+loc, debug=True)
        logMsg('DEBUG: xPPScorr...done')

    def doPPPcorr(self):
# find PPP Correction & apply
        if not self.optionsDict['reProcess'] :
            logMsg("DEBUG: doPPPCorr: reprocessing disabled, skipping")
            return None

        logMsg('DEBUG: PPCorr...')
        for loc in self.dbDict.keys():
            dat = self.dbDict[loc]
            if dat.empty:
                logMsg("DEBUG: empty data for location:",loc,"skipping")
                continue
            keys = dat.keys()
            if ('rxClkBias_ns' not in keys) or ('rx_clk_ns' not in keys) or ('dTCorr' not in keys) :
                #raise Exception("Data needed for PP corrections not found")
                logMsg("DEBUG: insufficient data for PPP correction, loc:",loc,", skipping")
                continue
            logMsg("DEBUG: loc:",loc,":",dat)
            dat['PPCorr'] = dat.rxClkBias_ns - dat.rx_clk_ns
            dat['dTPPCorr'] = dat.dTCorr - dat.rxClkBias_ns + dat.rx_clk_ns
            #dat['dT-StnClkOff'] = dat.dT_ns - dat.rx_clk_ns

            self.__previewDF(dat[['dT_ns','PPCorr','dTPPCorr']],title='PPPCorrectoins:'+loc,debug=True)

        logMsg('DEBUG: PPCorr...done')

    def save(self, suffix='', type='hdf'):
        logMsg('DEBUG: saving database to file...')
        fileName = self.options.outputPrefix
        ext='.hdf5'
        if fileName:
            fileName += ext+suffix
            logMsg("DEBUG: saving to HDF5 store in file",fileName)
        #with pandas.HDFStore(fileName+'.hdf5') as store:
            store = pandas.HDFStore(fileName)
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

    #def plotAllInOne( self, dataFrame, dataTypeList=['dT_ns','dTCorr','dTPPCorr'] ):
    def __plotAllInOne( self, dfView, loc, figure ) :
        logMsg('DEBUG: plotAllInOne...')
        if loc == None:
            raise Exception("ERROR: cannot plotAllInOne() with out loc= value")
        fig = figure
        axes = fig.gca()
        for name in dfView.keys() :
            if name in self.optionsDict['resampleDataBeforePlotList'] :
                seq = dfView[name].resample(self.optionsDict['resamplePlot'] )
            else:
                seq = dfView[name]
            color = self.optionsDict['tofPlotPref']['color'+':'+loc][name]
            marker = self.optionsDict['tofPlotPref']['marker'+':'+loc][name]
            label = '_nolegend_'
            if loc == 'nu1':
                label = name
            seq.plot(ax=axes,color=color,marker=marker,label=label,fillstyle='full')
        #title = self.optionsDict['description']
        #fig.suptitle(title)
        #axes.set_ylabel('dT (ns)')
        #axes.xaxis.set_minor_locator(AutoMinorLocator())
        #fig.subplots_adjust(bottom=0.08)
        #plt.legend(loc='best').get_frame().set_alpha(0.8)

        logMsg('DEBUG: plotAllInOne: ...done')
        return fig

    def checkNames(self, dataFrame, nameList ):
        '''chech each name against the keys in data frame.  Return a new list
        of names that are valid.  Generate warning if any names had to be dropped.
        '''
        logMsg('DEBUG: checkNames ...')
        newList = []
        keys = dataFrame.keys()
        for name in nameList:
            if name in keys:
                newList.append(name)
            else:
                logMsg("WARNING: checkNames: dataFrame doesn't contain key/name:",name,", dropped" )
                #TODO raise Exception("WARNING:")
        logMsg('DEBUG: checkNames ...done')
        return newList

    def __plotListForEachLoc(self, dataFrameDict, nameList, figure ):
        if nameList == []:
            raise Exception("ERROR: plotListForEachLoc need list of data types/names/columns to plot")
        logMsg('DEBUG: plotListForEachLoc ...')
        for loc in self.locations() :
            logMsg('DEBUG: plotListForEachLoc: working on loc:',loc)
            df = dataFrameDict[loc]
            newNameList = self.checkNames(df,nameList)
            if newNameList == list() :
                logMsg('DEBUG: plotListForEachLoc: none of the requested data types could be found for plotting, loc:',loc,', skipping' )
                continue
            subDF = df[newNameList]
            self.__plotAllInOne( subDF, loc=loc, figure=figure )
        logMsg('DEBUG: plotListForEachLoc ...done')
        return figure

    def plotType2new(self,dataFrameDict ):
        logMsg('DEBUG: plotType2new...')
        fig = plt.figure()
        axes = fig.gca()
        axes.format_xdata = self.xDataDateFormatter
        dataNameList = ['dT_ns','xPPSOffset','dTCorr','rxClkBias_ns','rx_clk_ns','dTPPCorr','PPCorr','dTCorr_avg','dTPPCorr_avg']
        self.__plotListForEachLoc( dataFrameDict, nameList=dataNameList , figure=fig )

        title = self.optionsDict['description']
        plt.suptitle(title)
        plt.ylabel('dT (ns)')
        legend = plt.legend(loc='best')
        if hasattr(legend,'get_frame') :
            legend.get_frame().set_alpha(0.8)
        axes.xaxis.set_minor_locator(AutoMinorLocator())
        axes.xaxis.set_major_formatter(self.majorTickFormater)
        fig.subplots_adjust(bottom=0.08)

        # auto zoom to important bits
        if 'dT_ns' in self.dbDict['nu1'].keys():
            dTmax=self.dbDict['nu1']['dT_ns'].max()
            dTmin=self.dbDict['nu1']['dT_ns'].min()
            axes.set_ylim(bottom=dTmin-5,top=dTmax+5)
        
        #plt.draw() # redraw
        plt.show()
        logMsg('DEBUG: plotType2new...')

    def plotType1(self, dataFrame):
        logMsg('DEBUG: plotType1...')
        plt.figure()
        for key in dataFrame.keys():
            dataFrame[key].plot(grid=True,style=tofAnalayser.styleMap[key])
        plt.show()
        logMsg('DEBUG: plotType2: done...')

    def viewBasic(self):
        '''gather data from different locations into one plot'''
        logMsg('DEBUG: viewBasic...')
        self.plotType2new(self.dbDict)
        logMsg('DEBUG: viewBasic...done')

    def __dropNAN(self):
        '''drop unusable values'''
        logMsg("DEBUG: droping NAN values...")
        for loc in self.dbDict.keys():
            dat = self.dbDict[loc]
            self.dbDict[loc] = dat.dropna(how='any')
            logMsg("DEBUG: after dropna:",dat)
        logMsg("DEBUG: droping NAN values...done")

    def analyse(self):
        logMsg('DEBUG: Analyse...')
        self.viewBasic()
        logMsg('DEBUG: Analyse...done')

    def doAvg(self):
        if not self.optionsDict['reProcess'] :
            logMsg("DEBUG: doPPPCorr: reprocessing disabled, skipping")
            return None

        window = self.optionsDict['avgWindow']
        for loc in self.locations():
            db = self.dbDict[loc]
            avgDataList = ['dTCorr','dTPPCorr']
            for name in avgDataList:
                if db.empty:
                    logMsg("DEBUG: empty data for location:",loc,"skipping")
                    continue
                if name not in db.keys() :
                    #raise Exception("Data needed for PP corrections not found")
                    logMsg("DEBUG: insufficient data for Averaging, loc:",loc,", skipping")
                    continue
                avgname=name+'_avg'
                db[avgname] = pandas.rolling_mean( db[name], window )

    def doCalculations(self):
        if not self.optionsDict['reProcess'] :
            logMsg("DEBUG: doCalculations: reprocessing disabled, skipping")
            return None
        self.doXPPScorr()
        #self.preview()
        self.doPPPcorr()
        #self.preview()
        self.doAvg()
        self.preview()


## MAIN ##
def runMain():
    tof = tofAnalayser()
    tof.configure()
# import main data
    tof.loadData()
    if tof.optionsDict['storeOnly'] :
        exit(0)
# store data
    tof.save()
# organize data
    tof.prep()
# import correcitions
# apply corrections
    tof.doCalculations()
# store data
    tof.save(suffix='.postCalc')
# analyse data
    tof.analyse()
# store analysed data
    #tof.save()
# overview plot
# find sub-series
# reanalyse
# replot


if __name__ == "__main__" :
    try:
        runMain()
    except KeyboardInterrupt as e:
        '''relax, exit but supress traceback'''
