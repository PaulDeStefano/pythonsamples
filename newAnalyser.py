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
from calendar import timegm
import scipy as sp

# use tex to format text in matplotlib
#rc('text', usetex=True)
mpl.rcParams['figure.dpi']          = 100
# large figures
mpl.rcParams['figure.figsize']      = (14,9)
mpl.rcParams['figure.facecolor']    = '0.75'
mpl.rcParams['figure.subplot.left'] = 0.07
mpl.rcParams['figure.subplot.bottom'] = 0.08
mpl.rcParams['figure.subplot.right'] = 0.96
mpl.rcParams['figure.subplot.top']  = 0.96 
mpl.rcParams['font.size']           = 9

# small figures
mpl.rcParams['figure.figsize']      = (7.0,5.0)
mpl.rcParams['figure.subplot.left'] = 0.08
mpl.rcParams['figure.subplot.bottom'] = 0.25
mpl.rcParams['figure.subplot.right'] = 0.95
mpl.rcParams['figure.subplot.top']  = 0.94 
mpl.rcParams['font.size']           = 12

mpl.rcParams['grid.alpha']          = 0.4
mpl.rcParams['axes.grid']           = True
#mpl.rcParams['axes.facecolor']      = '0.90'
mpl.rcParams['axes.facecolor']      = '1'
mpl.rcParams['lines.linestyle']     = None
mpl.rcParams['lines.marker']        = '+'
mpl.rcParams['lines.markersize']    = 3
mpl.rcParams['lines.antialiased']   = True

mpl.rc('legend'
        ,markerscale=2.0
        ,fontsize='small')
mpl.rc('text'
        ,usetex=False )
mpl.rcParams['xtick.major.size']    = 10.0
mpl.rcParams['xtick.major.width']   = 2.0
mpl.rcParams['xtick.labelsize']     = 'medium'
mpl.rcParams['xtick.direction']     = 'inout'
mpl.rcParams['ytick.major.size']    = 10.0
mpl.rcParams['ytick.major.width']   = 2.0
mpl.rcParams['ytick.labelsize']     = 'medium'
mpl.rcParams['ytick.direction']     = 'inout'

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

def getUniqs(seq):
    seen = set()
    seen_add = seen.add
    return [ x for x in seq if x not in seen and not seen_add(x)]

def getDups(seq):
    seen = set()
    seen_add = seen.add
    dups = set()
    for x in seq:
        if x in seen: dups.add(x)
        seen_add(x)
    return dups

def logRange(minPower,maxPower,base=10):
    r = list()
    power = minPower
    while power < maxPower :
        start = base**power
        end = base**(power+1)
        newr = range(start, end, start)
        r = r + newr
        power += 1
    return r

def avar2sample(phase1, phase2):
    freq = phase2 - phase1
    return (1.0/2.0)*np.mean(np.square(freq))

'''
def modAVAR(phases,n,tau0) :
    phaseArray = np.array(phases)
    N = len(phaseArray)
    const = (1.0 / (2*n**4 * tau0**2 * (N-3*n+1) ) )
    jStart = 0
    jEnd = N - 3*n 
    phaseSamples = phaseArray[jStart:jEnd:n]

    for j in xrange(jStart,jEnd,n) :
        iStart = j
        iEnd = j+n-1
        for i in xrange(
'''

def allan(phases, tau, base=1):
    """
    allan(t, y, tau, base)
    Allan variance calculation

    Input variables:
    ----------------
    t : time of measurement
    freq : measured frequency
    tau : averaging time
    base : base frequency

    Output variables:
    -----------------
    s : Squared Allan variance
    """
    phaseArray = np.array(phases)
    #logMsg("DEBUG: allan: got phases",phaseArray[0:10])
    freq = phaseArray[1:] - phaseArray[0:-1]
    #logMsg("DEBUG: allan: got freq",freq[0:5])
    # Divide time up to 'tau' length units for averaging
    times = np.arange(0,freq.size-1, tau)
    #logMsg("DEBUG: allan: got times",times[0])
    # Create temporary variable for fractional frequencies
    vari = np.zeros(len(times))
    for tstep in range(0, len(times)):
            # Get the data within the time interval
        data = freq[ times[tstep] : (times[tstep] + tau) ]
        # Fractional frequency calculation
        vari[tstep] = (sp.mean(data) - base) / base
    # Squared Allan variance
    s = sp.mean((vari[0:-1] - vari[1:]) ** 2) / 2
    #logMsg("DEBUG: allan: got avar",s)
    return s 

def rms(seq):
    array = np.array(seq)
    return np.sqrt(np.mean(np.square(array)))

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
            , 'master'          : 'iso8601,dT,xPPSOffset,rxClkBias,rx_clk_ns,dT_ns,rxClkBias_ns,PPCorr,dTPPCorr,dTCorr_avg,dTCorr_avgerr,dTPPCorr_avg,dTPPCorr_avgerr' 
            , 'csvSave'         : 'unixtime,dT,xPPSOffset,rxClkBias,rx_clk_ns,dT_ns,rxClkBias_ns,PPCorr,dTPPCorr,dTCorr_avg,dTCorr_avgerr,dTPPCorr_avg,dTPPCorr_avgerr' 
            }
    formatDict['default'] = formatDict['ticFinal']  # alias names for formats
    formatDict['hdf'] = formatDict['master']        # not used
    formatDict['csvOleg'] = re.sub(' ',',',formatDict['csvSave'])
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
                ,'dTCorr' : 'green'
                ,'xPPSOffset': 'grey'
                ,'rxClkBias': 'lightblue'
                ,'rxClkBias_ns': 'blue'
                ,'rx_clk_ns': 'magenta'
                ,'PPCorr' : 'yellow'
                ,'dTPPCorr' : 'darkcyan'
                ,'dT-StnClkOff' : 'orange'
                ,'dTCorr_avg' : 'green'
                ,'dTPPCorr_avg' : 'darkcyan'
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
    majorTickFormater = mdates.DateFormatter('%d %b #%j\n%H:%MZ')

    def configPylab(self):
        #mpl.rcParams['axes.format_xdata']       = self.xDataDateFormatter
        #mpl.rcParams['axes.xaxis.set_major_locator']      = self.majorTickFormater
        #mpl.rcParams['axes.xaxis.set_minor_locator']      = AutoMinorLocator()
        pass

    def configMPLaxis(self, ax):
        ax.xaxis.set_minor_locator(AutoMinorLocator())          # enable minor ticks
        ax.yaxis.set_minor_locator(AutoMinorLocator())
        ax.xaxis.set_major_formatter(self.majorTickFormater)    # use explict data format on x axis
        ax.format_xdata = self.xDataDateFormatter               # use slightly different fmt for pointer values

    def configMPLaxes(self, axes):
        if type(axes) == type(list()):
            for ax in axes:
                self.configMPLaxis(ax)
        else:
            '''assume axes'''
            ax = axes
            self.configMPLaxis(ax)
            axes.format_xdata = self.xDataDateFormatter


    def configMPLfig(self, fig):
        self.configMPLaxes(axes=fig.gca())
        #fig.subplots_adjust(bottom=0.08) #lg
        fig.subplots_adjust(bottom=0.16) #sm

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
        parser.add_argument('--histogram', action='store_true', default=False, help='Make histograms')
        parser.add_argument('--histbins', nargs='?', default=50, help='Number of bins in histograms')
        parser.add_argument('--shiftOffset', '-s', nargs='?', default=0, help='shift time of xPPSOffset corrections wrt. TIC measurements by this many seconds')
        parser.add_argument('--importLimit', '-L', nargs='?', default=1E7, help='limit imported data to the first <limit> lines')
        parser.add_argument('--outputPrefix', nargs='?', default=False, help='Save the results of the applied xPPSOffset corrections to a series of files with this name prefix')
        parser.add_argument('--frequency', '-F', action='store_true',default=False, help='Calculate Frequency Departure of all time series analysed')
        parser.add_argument('--fft', '-S', action='store_true',default=False, help='Calculate Spectral Density (Fourier Transform) of any time series')
        parser.add_argument('--corr', '-C', nargs='?', help='File continating "correction" values (from getCorrData.sh)')
        parser.add_argument('--showFormats', action='store_true', default=False, help='Show a list of known formats')
        parser.add_argument('--loadSaved', nargs='?', default=False, help='Load a previously saved data set from this file')
        parser.add_argument('--forceReProcess', action='store_true', default=False, help='Froce reprocessing of data loaded from saved data files')
        parser.add_argument('--hdf5', action='store_true', default=True, help='Use HDF5 file format to store data.  Default is TRUE')
        parser.add_argument('--csv', action='store_true', default=False, help='Use CSV file format to store data.')
        parser.add_argument('--debug', action='store_true', default=False, help='Force extra preview plots during calculations')
        parser.add_argument('--avgWindow', nargs='?', default=100000, help='Calculate rolling average (of selected data) with specified window size (in units of samples, i.e. secs)' )
        parser.add_argument('--resamplePlot', nargs='?', default=100000/10, help='Select sub-sample size for plotting selected data types (averaging types). Default=1/4 of avgWindow => 5 plot points in each window' )
        parser.add_argument('--previewPercent', nargs='?', default=20, help='Sub-sample size for all *preview* plotting' )
        parser.add_argument('--storeOnly', action='store_true', default=False, help='after loading data, save it (if outputFile given), and quit.  Useful for consolidating data into HDF file, faster reading later')
        parser.add_argument('--colsToCSV', nargs='?', default='csvSave', help='Specify the format, explicitly, or the format name to use when writing to CSV files')
        parser.add_argument('--kdePercent', nargs='?', default=25, help='Sub-sample percent for calculating KDE (of selected datatypes)' )
        parser.add_argument('--preview', action='store_true', default=False, help='Force preview before analysis')

        self.options = parser.parse_args()
        args = self.options

        optionsDict = self.optionsDict
        optionsDict['inputFiles'] = args.fileList
        optionsDict['description'] = args.desc
        optionsDict['maxEpochGap'] = float(args.gap)
        optionsDict['offsetFile'] = args.offsets
        optionsDict['negOffset'] = args.negOffset
        optionsDict['numBins'] = int(args.histbins)
        optionsDict['histogram'] = args.histogram
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
        optionsDict['hdf5'] = args.hdf5
        optionsDict['csv'] = args.csv
        optionsDict['avgWindow'] = int(args.avgWindow)
        if args.resamplePlot == None:
            optionsDict['resamplePlot'] = str(int(np.floor(optionsDict['avgWindow'] / 5)))+'S'
        else:
            optionsDict['resamplePlot'] = str(int(args.resamplePlot))+'S'
        optionsDict['previewPercent'] = int(args.previewPercent)
        optionsDict['storeOnly'] = args.storeOnly
        optionsDict['colsToCSV'] = args.colsToCSV
        optionsDict['kdeResamplePCT'] = int(args.kdePercent)
        optionsDict['preview'] = args.preview

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
        optionsDict['tofPlotPref']['color:sk']['dT_ns']         = 'red'
        optionsDict['tofPlotPref']['color:nd280']['dT_ns']      = 'red'
        optionsDict['tofPlotPref']['marker:sk']['dT_ns']        = 'x'
        optionsDict['tofPlotPref']['marker:nd280']['dT_ns']     = 'x'

        '''allow different shift values per location'''
        self.parseDictOption( 'shiftMap',self.options.shiftOffset,delim2='=' )

        '''When plotting, resample these datatypes only'''
        masterFromatList = self.formatDict['master']
        logMsg("DEBUG: configure: master formats:",masterFromatList )
        resampleList = filter( lambda x: re.search('_avg', x) ,masterFromatList.split(',') )
        logMsg("DEBUG: configure: resampleList:", resampleList )
        optionsDict['resampleDataBeforePlotList'] = filter( lambda x: re.search('_avg', x) , resampleList )
        '''cacluate errors for these types of data'''
        optionsDict['calcErrList'] = ['dTCorr_avg','dTPPCorr_avg']

        logMsg('DEBUG: harvested coniguration:',optionsDict)

        # set matplotlib configuration
        self.configPylab()

        if args.showFormats:
            for fmt in self.formatDict:
                print(fmt)

#print("DEBUG: negOffset:" + str(negOffset) )


    def __getResampleSize(self, percent=10):
        return str(int(np.floor(100/percent)))+'S'

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
                ,sort=False
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
                newData.tz_localize('UTC')
                self.addData(newData, loc=loc)

            if not self.optionsDict['reProcess']:
                '''we already loaded some saved data from, so reverse the flag
                that prevents re-processing the data because more data has been
                added and we should start over'''
                self.optionsDict['reProcess'] = True

        else:
            logMsg("WARNING: no new inputFiles to load")
        
        # store data
        self.save()

        ''' check for duplicates indecies'''
        logMsg("DEBUG: checking for duplcates")
        for db in self.dbDict.values() :
            dupList = db.index.get_duplicates()
            if list(dupList) != list():
                logMsg("DEBUG: loaded data contains duplicate index:",dupList,"len:",len(dupList) )
                raise Exception("ERROR: loaded data contains duplicate index")

        ''' Drop data we don't need '''
        self.__dropNAN()

        # store data
        self.save()
        if self.optionsDict['storeOnly'] :
            logMsg("DEBUG: storeOnly specified, exiting now.")
            exit(0)

        self.preview(previewPoint="After Loading", debug=True)


    def _getFormat(self,fmt):
        if fmt in self.formatDict.keys() :
            return self.formatDict[fmt]
        elif re.search(fmt,self.formatDict['master']) :
            '''okay, at least this one could be meaningful'''
            return fmt
        else :
            raise Exception("DEBUG: couldn't interpret format specification: "+fmt)

    def __decodeFormat(self, fmt):
        delimiter = None
        names = list()

        fullFmt=self._getFormat(fmt)
        
        if re.search('\s', fullFmt):
            '''whitespace delimited format'''
            #logMsg('DEBUG: _loadFile: using whitespace as delimiter to read file')
            delimiter=' '
        else:
            #logMsg('DEBUG: _loadFile: using comma as delimiter to read file')
            delimiter=','
        
        names=fullFmt.split(delimiter)
        return [ delimiter, names ]

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

        logMsg("DEBUG: previewDF ",title,"...")
        #logMsg('DEBUG: preview: \n', previewDF.describe() )
        if None == title:
            title=self.options.desc
        #print previewDF.head(2)
        #print previewDF.tail(2)
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
        fig = plt.gcf()
        self.configMPLfig(fig)
        plt.suptitle('Preview:'+title+' (downsampled)')
        plt.show()
        logMsg("DEBUG: previewDF ...done")

    def preview(self,previewPoint=None,debug=False):
        if debug and not self.options.debug:
            return

        logMsg('DEBUG: previewing at ',previewPoint,'...')
        logMsg('DEBUG: ', self.dbDict.keys() )
        title = self.optionsDict['description']
        for loc in self.dbDict.keys():
            dat = self.dbDict[loc]
            if dat.empty:
                logMsg("DEBUG: empty data for location:",loc,"skipping")
                continue
            self.__previewDF(dat,title=title+':'+loc+'@'+previewPoint,debug=debug)

        logMsg('DEBUG: previewing at ',previewPoint,'...done')

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
        #self.__dropNAN()

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
        ''' apply xppsoffset '''
        logMsg("DEBUG: reProcess: ",self.optionsDict['reProcess'])
        if not self.optionsDict['reProcess'] :
            logMsg("DEBUG: doXPPScorr: reprocessing disabled, skipping")
            return None

        logMsg('DEBUG: xPPScorr...')
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
            self.__previewDF( dat[['dT_ns','dTCorr','xPPSOffset']] ,title='@xPPSOffset:'+loc, debug=True)
        logMsg('DEBUG: xPPScorr...done')

    def doPPPcorr(self):
        ''' find PPP Correction & apply '''
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

            self.__previewDF(dat[['dT_ns','PPCorr','dTPPCorr']],title='@PPPCorrectoins:'+loc,debug=True)

        logMsg('DEBUG: PPCorr...done')


    def __addUNIXTimeColumn(self, dataFrame ):
        if 'unixtime' in dataFrame.keys():
            return dataFrame
        index = dataFrame.index
        timeList = [ timegm(x.utctimetuple()) for x in index ]
        newColumn = pandas.DataFrame( timeList, index=index )
        dataFrame['unixtime'] = newColumn
        logMsg("DEBUG:addUNIXTime: head",dataFrame.head() )
        logMsg("DEBUG:addUNIXTime: tail",dataFrame.tail() )
        return dataFrame
    
    def __createUNIXtime(self):
        for loc in self.locations():
            logMsg("DEBUG: creating UNIX timestamp from DataFrame index for location:",loc)
            db = self.dbDict[loc]
            self.__addUNIXTimeColumn(db)

    def saveToFile(self, fileNamePrefix, suffix='', typ='hdf' ):
        logMsg('DEBUG: saveToFile: saving database to file...')
        if  typ == 'hdf' :
            fileName = fileNamePrefix+'.hdf5'+suffix
            logMsg("DEBUG: saving to HDF5 store in file",fileName)
            #with pandas.HDFStore(fileName+'.hdf5') as store:
            store = pandas.HDFStore(fileName)
            for loc in self.dbDict.keys():
                store[loc] = self.dbDict[loc]
            store.close()
            del store
        elif typ == 'csv' :
            fmt = self.optionsDict['colsToCSV']
            separator, names = self.__decodeFormat(fmt)
            logMsg("DEBUG: saveToFile: saving CSV, with separator:'"+separator+"' and columns:",names)
            #self.__createUNIXtime()
            for loc in self.locations():
                db = self.dbDict[loc]
                cols = set(names).intersection(db.keys())
                if cols == set():
                    continue
                #newdb = np.round(db,3)
                newdb = db
                self.__addUNIXTimeColumn(db)
                fileName =  fileNamePrefix+'.'+loc+'.csv'+suffix
                logMsg("DEBUG: saveToFile: saving to CSV store in file",fileName)
                newdb.to_csv(fileName
                        ,header=True
                        ,cols=cols
                        ,sep=separator
                        ,index=True
                        ,index_label='utc'
                        ,na_rep='NaN'
                        )
                del newdb

        else :
            logMsg("DEBUG: saveToFile: couldn't save data, unrecognized output type:",typ)

        logMsg('DEBUG: saveToFile: saving database to file...done')

    def save(self, suffix='', typ='hdf'):
        logMsg('DEBUG: save: saving database...')
        fileName = self.options.outputPrefix
        if not fileName:
            logMsg("DEBUG: save: couldn't write, no outputFile specified")
            return
        if self.optionsDict['csv']:
            typ='csv'
        self.saveToFile(fileName, suffix=suffix,typ=typ )
        logMsg('DEBUG: save: saving database...done')

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
                db = store[storeKey]
                #db = np.round( db , 6 )
                self.dbDict[loc] = db

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
            
            '''plot with erro bars, if data exists'''
            color = self.optionsDict['tofPlotPref']['color'+':'+loc][name]
            marker = self.optionsDict['tofPlotPref']['marker'+':'+loc][name]
            '''limit ledend to only nu1 items just to reduce legend size'''
            label = '_nolegend_'
            if loc == 'nu1':
                label = name
            seq.plot(ax=axes,color=color,marker=marker,label=label,fillstyle='full')
            errVals = None
            if name+'err' in self.dbDict[loc].keys() :
                logMsg("DEBUG: plotAllInOne: has errorbars:",name)
                axes = fig.gca()
                df = self.dbDict[loc]
                errVals = df[name+'err'].ix[ seq.index ]
                print errVals.tail()
                plt.errorbar(axes=axes,x=seq.index.values,y=seq.values,yerr=errVals,label=None)
            else:
                logMsg("DEBUG: plotAllInOne: no errorbards for:",name)

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
            if name in keys and len(dataFrame[name]) > 0:
                newList.append(name)
            else:
                logMsg("WARNING: checkNames: dataFrame doesn't contain key/name or name has no data:",name,", dropped" )
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

    def plotType2new(self,dataFrameDict,nameList=None,fig=None,zoomData='dT_ns' ):
        logMsg('DEBUG: plotType2new...')

        show = False
        if fig == None:
            fig = plt.figure()
            show = True
        if nameList == None:
            dataNameList = ['dT_ns','xPPSOffset','dTCorr','rxClkBias_ns','rx_clk_ns','dTPPCorr','PPCorr','dTCorr_avg','dTPPCorr_avg']
        else:
            dataNameList = nameList
        axes = fig.gca()
        self.__plotListForEachLoc( dataFrameDict, nameList=dataNameList , figure=fig )

        title = self.optionsDict['description']
        plt.suptitle(title)
        plt.ylabel('dT (ns)')
        legend = plt.legend(loc='best')
        if hasattr(legend,'get_frame') :
            legend.get_frame().set_alpha(0.8)
        self.configMPLfig(fig)

        # auto zoom to important bits
        if zoomData in dataNameList :
            if list() != self.dbDict['nu1'].keys():
                if zoomData in self.dbDict['nu1'].keys():
                    dTmax=self.dbDict['nu1'][zoomData].max()
                    dTmin=self.dbDict['nu1'][zoomData].min()
                    axes.set_ylim(bottom=dTmin-5,top=dTmax+5)
        
        #plt.draw() # redraw
        if show == True:
            logMsg('DEBUG: plotType2new: showing...')
            plt.show()
        logMsg('DEBUG: plotType2new...done')

    def plotType1(self, dataFrame):
        logMsg('DEBUG: plotType1...')
        plt.figure()
        for key in dataFrame.keys():
            dataFrame[key].plot(grid=True,style=tofAnalayser.styleMap[key])
        logMsg('DEBUG: plotType1: showing...')
        plt.show()
        logMsg('DEBUG: plotType2: done...')

    def plotHist(self, dbDict, bins=50):
        if not self.optionsDict['histogram'] :
            logMsg("DEBUG: skipping histogram (need --histogram)")
            return

        logMsg("DEBUG: doHist:...")
        keys = dbDict.keys()
        #histKeys = ['dT_ns','dTCorr','dTPPCorr','dTPPCorr_avg']
        histKeys = ['dT_ns','dTCorr','dTPPCorr']
        sampleSize = self.__getResampleSize(self.optionsDict['kdeResamplePCT'])
        #bins=50
        for loc in keys:
            df = dbDict[loc]
            names = list( set(histKeys).intersection(set(df.keys())) )
            #logMsg("DEBUG: using names:",names)
            dfView = df[names]
            dfView = dfView.resample(sampleSize)
            dfView = dfView.dropna()
            #logMsg( dfView.head() )
            #logMsg("DEBUG: using dfView:",dfView.head())
            self.__previewDF(dfView, title=loc+'@plotHist',debug=True)
            #dfView.hist(bins=bins)
            #fig=plt.gcf()
            #fig.suptitle(loc)
            #TODO:make histogram and kde on same plot
            dfView.plot(kind='kde',subplots=True,style='k-',title=loc+' (downsampled)')

        logMsg("DEBUG: doHist: showing...")
        plt.show()
        logMsg("DEBUG: doHist:...done")

    def viewProgressive(self):
        '''show progression of corrections'''
        logMsg('DEBUG: viewProgressive...')

        fig = plt.figure()
        nameList = ['dT_ns']
        self.plotType2new(self.dbDict,nameList=nameList,fig=fig)
        ylim = fig.gca().get_ylim()  # save limits for other plots

        #fig = plt.figure()
        #nameList = ['dT_ns','dTCorr']
        #self.plotType2new(self.dbDict,nameList=nameList,fig=fig)
        fig.gca().set_ylim(ylim)
        fig = plt.figure()
        nameList = ['dTCorr']
        self.plotType2new(self.dbDict,nameList=nameList,fig=fig)
        fig.gca().set_ylim(ylim)

        #fig = plt.figure()
        #nameList = ['dTCorr','dTPPCorr']
        #self.plotType2new(self.dbDict,nameList=nameList,fig=fig)
        fig = plt.figure()
        nameList = ['dTPPCorr']
        self.plotType2new(self.dbDict,nameList=nameList,fig=fig)
        fig.gca().set_ylim(ylim)

        fig = plt.figure()
        nameList = ['rxClkBias_ns','rx_clk_ns']
        self.plotType2new(self.dbDict,nameList=nameList,fig=fig)

        logMsg('DEBUG: viewProgressive: showing...')
        plt.show()
        logMsg('DEBUG: viewProgressive...done')

    def viewBasic(self):
        '''gather data from different locations into one plot'''
        logMsg('DEBUG: viewBasic...')
        self.plotHist(self.dbDict)
        self.plotType2new(self.dbDict)
        logMsg('DEBUG: viewBasic...done')

    def viewSimple(self):
        '''show progression of corrections'''
        logMsg('DEBUG: viewSimple...')

        fig = plt.figure()
        nameList = ['dT_ns','dTCorr','dTPPCorr','dTCorr_avg','dTPPCorr_avg']
        self.plotType2new(self.dbDict,nameList=nameList,fig=fig)

        logMsg('DEBUG: viewSimple: showing...')
        plt.show()
        logMsg('DEBUG: viewSimple...done')

    def __dropNAN(self):
        '''drop unusable values'''
        logMsg("DEBUG: droping NAN values...")
        for loc in self.dbDict.keys():
            dat = self.dbDict[loc]
            if 'dT' not in dat.keys() :
                continue
            self.dbDict[loc] = dat[ - pandas.isnull(dat['dT']) ]  # safe, only missing dT
            #self.dbDict[loc] = dat.dropna(how='any')  # all rows missing data in *any* column
            logMsg("DEBUG: after dropna:",dat)
        logMsg("DEBUG: droping NAN values...done")

    def avarBad(self, phaseList, tau0_samples, mStride, overlap=False):
        phases = np.array( phaseList )
        if overlap : tau = 1
        else : tau = mStride * 1
        #logMsg('DEBUG: avar: starting on sequence of length:',len(phases))
        #phaseRange = xrange(0,len(phases),tau)
        diff2List = list()
        N = len(phases)
        logMsg('DEBUG: avar: starting on sequence of length:',len(phases),'w/ N={},tau={},mStride={}'.format(N,tau,mStride) )
        #for i in xrange(0,(N-2*mStride+1),mStride) :
        for i in xrange(0,(N-2*mStride)+1,mStride) :
            y1 = phases[i+mStride] - phases[i]
            y2 = phases[i+(2*mStride)] - phases[i+mStride]
            #logMsg('DEBUG: y1:',y1,' y2:',y2)
            diff2List.append( y2 - y1 )
        diff2 = np.array( diff2List ) # convert to np.array
        M = diff2.size
        #avar = np.sum( np.square(diff2) ) * (1/(2*mStride**2*(M-2*mStride+1)))
        logMsg('DEBUG: avar: diff2={}..{}'.format(diff2[0],diff2[diff2.size-1]) )
        squared = np.square(diff2)
        logMsg('DEBUG: avar: squared={}..{}'.format(squared[0],squared[diff2.size-1]) )
        summed = np.sum( squared ) 
        logMsg('DEBUG: avar: sum = ',summed )
        avar = np.sum( np.square(diff2) ) * (1.0/(2*(M-1)))
        return avar

    """
        def adev(self, phaseList, tau0_samples, m_avgStride, overlap=False):
        #assert( type(phases) == np.ndarray )
        phases = np.array( phaseList )
        N = len(phases)
        logMsg('DEBUG: adev: starting on sequence of length:',len(phases))
        tau = tau0_samples * m_avgStride
        if overlap: stride = tau
        else: stride = tau0_samples
        diff2 = list()
        timesList = xrange(1,N,stride)
        logMsg('DEBUG: adev: timesList:{}, tau:{}, step:{}'.format(timesList,tau,step) )

        for i in timesList:
            y1 = phases[i+tau] - phases[i] # first first diff/frac.freq.
            y2 = phases[i] - phases[i-tau] # second first diff/frac.freq.
            diff2.append(y1 - y2)         # second difference of frac. freq

        logMsg('DEBUG: adev: diff2:',diff2)
        if len(diff2) > 0 : adev = np.sqrt( np.sum( (diff2)/(2.0*(N-2)) ) )
        else: adev = 0.0
        return adev
    """
        
    def viewFrequency(self):
        '''Show the frecuency anlaysis I.E.: frac freq error, AVAR, TDEV, etc
        '''
        
        logMsg('DEBUG: viewFrequency:...')
        avgSamples = logRange(1,7)
        measUnit = 10**-9 #seconds
        #seq = self.dbDict['nu1']['dT_ns'].dropna() * measUnit
        name = 'dTPPCorr'
        loc = 'nu1'
        seq = self.dbDict[loc][name].dropna()
        seqLength = len(seq)
        adevList = list()
        avgCompleteList = list()
        tau0 = 1 # time between samples, (in samples, currently)
        for m in avgSamples:
            if m > seqLength: 
                break  # stop if we don't have enough points to do more averaging
            #avar = self.avar( seq, tau0_samples=1, mStride=m, overlap=False)
            avar = allan( seq,tau=m*tau0, base=tau0)
            logMsg('DEBUG: viewFrequency: avar:',avar,' avg period:',m)
            adevList.append( np.sqrt(avar)*measUnit )
            avgCompleteList.append(m)

        plt.figure()
        plt.loglog(avgCompleteList, adevList , linestyle='-', marker='o', color='b')
        plt.suptitle('ADEV @'+loc+':'+name)
        logMsg('DEBUG: viewFrequency: showing...')
        plt.show()

        #avarSeq = pandas.expanding_apply( seq,self.avar,min_periods=10 ) # too slow!
        #avarSeq.plot(logy=True,title='test AVAR dTCorr nu1')

        logMsg('DEBUG: viewFrequency: done')

    def analyse(self):
        logMsg('DEBUG: Analyse...')
        if self.optionsDict['preview'] == True:
            self.preview(previewPoint='Before analysis',debug=False)  # always preview here
        self.viewSimple()
        self.viewProgressive()
        self.viewFrequency()
        self.viewBasic()
        logMsg('DEBUG: Analyse...done')

    def doAvg(self):
        if not self.optionsDict['reProcess'] :
            logMsg("DEBUG: doPPPCorr: reprocessing disabled, skipping")
            return None

        logMsg("DEBUG: doAvg: ...")
        window = self.optionsDict['avgWindow']
        for loc in self.locations():
            db = self.dbDict[loc]
            avgDataList = ['dTCorr','dTPPCorr']
            for name in avgDataList:
                if db.empty:
                    logMsg("DEBUG: doAvg: empty data for location:",loc,"skipping")
                    continue
                if name not in db.keys() :
                    #raise Exception("Data needed for PP corrections not found")
                    logMsg("DEBUG: doAvg: insufficient data for Averaging, loc:",loc,", skipping")
                    continue
                newname=name+'_avg'
                logMsg("DEBUG: doAvg: calculating avg for ",name)
                db[newname] = pandas.rolling_mean( db[name], window )
                #print db[newname].tail()
                #TODO: db[avgname] = pandas.rolling_window( db[name], window, 'boxcar', center=True)
                '''do statistical error, too'''
                if newname in self.optionsDict['calcErrList'] :
                    errName=newname+'err'
                    '''
                    db[errName] = pandas.rolling_apply( 
                            db[name]
                            ,window,func=lambda x: np.sqrt( avar2sample( x[0]*1E-9,x[-1]*1E-9) )*window*1E9 )
                    '''
                    db[errName] = pandas.rolling_apply( 
                            db[name]
                            ,window,func=np.std )
                    #print db[errName].tail()
                    logMsg("DEBUG: doAvg: done calculating errors for ",newname)

        logMsg("DEBUG: doAvg: ...done")

    def doFreq(self):
        '''Calculate first difference (aka fractional freq. error) and second 
        differences.'''
        logMsg('DEBUG: doFreq: ...')
        freqNameList=['dTCorr','dTPPCorr']
        for db in self.dbDict.values():
            nameList = filter(lambda x: x in freqNameList, db.keys() )
            for name in nameList:
                logMsg('DEBUG: doFreq: working on datatype:',name)
                '''get the data sequence'''
                oldSeq = db[name]
                #dTPPCorr = pandas.rolling_mean(db['dTPPCorr'], window=100)
                '''calculate first difference'''
                diff1 = oldSeq - oldSeq.shift(1)
                diff1 = diff1.dropna()
                '''filter results statistically, kluge for non-contiguous data series'''
                stddev = diff1.std()
                mean = diff1.mean()
                withinLimits = (diff1 > mean-10*stddev) & (diff1 < mean + 10*stddev)
                diff1 = diff1[withinLimits]
                #dupList = getDups(list(diff1.index))
                #if list(dupList) != list():
                #    logMsg('DEBUG: doFreq: diff1 has duplcates:',dupList)
                #    raise Exception('ERROR: doFreq: diff1 has duplcates')
                '''store result'''
                db[name+'_1st'] = diff1
                #diff1.resample('3S').dropna().plot(kind='kde')
            self.__previewDF(db, title="in doFreq", debug=True)

        logMsg('DEBUG: doFreq: ...done')

    def doCalculations(self):
        if not self.optionsDict['reProcess'] :
            logMsg("DEBUG: doCalculations: reprocessing disabled, skipping")
            return None
        self.doXPPScorr()
        self.doPPPcorr()
        self.doAvg()
        self.doFreq()

        # store data
        self.save(suffix='.postCalc')
        self.preview(previewPoint='After Calcuations',debug=False)  # always preview here


## MAIN ##
def runMain():
    tof = tofAnalayser()
    tof.configure()
# import main data
    tof.loadData()
# organize data
    tof.prep()
# import correcitions
# apply corrections
    tof.doCalculations()
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
