%parameters
EMG=filteredEMG;
fs = 2000;
badchan = [];
padLen = 200;
initialization = 1;
NITER = 70;
nbextchan =1024;        
silthr = 0.7;
covfilter = 1;
covthr = 0.5;
differentialmode = 0;
peeloff_flag = 1;
peeloffwin = 0.025;
duplicatesthresh = 0.3;
CoVDR = 0.3;
contrastfunc = 'skew';
refineMU = 0;
preproc_flag = 0;


% 1. CALIBRATION (Run offline code once to get the filters)

Calib_data = decompose3(EMG, fs, badchan, padLen, initialization, NITER, nbextchan, silthr, covfilter, covthr, ...
    differentialmode, peeloff_flag, peeloffwin, duplicatesthresh, CoVDR, contrastfunc, refineMU, preproc_flag);


