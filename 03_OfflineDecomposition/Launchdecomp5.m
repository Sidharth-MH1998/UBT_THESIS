clc
clear;
close all;
%% Select and load the recording
[loadedFileName,loadedFilePath] = uigetfile('*.mat','Select the EMG file to decompose');

if isequal(loadedFileName,0)
    error('No .mat file was selected.');
end

loadedFile = fullfile(loadedFilePath,loadedFileName);
DataFile = load(loadedFile);
EMG = DataFile.signal; % Pass grid metadata together with the EMG data.

%% Parameters
fs = DataFile.signal.fsamp;
badchan = [];
padLen = 200;
initialization = 0;
NITER = 50;
nbextchan =1024;        
silthr = 0.9;
covfilter = 1;
covthr = 0.5;
differentialmode = 0;
peeloff_flag = 1;
peeloffwin = 0.025;
duplicatesthresh = 0.3;
CoVDR = 0.3;
contrastfunc = 'skew';
refineMU = 1;
preproc_flag = 1;


%% Calibration (run offline decomposition once to obtain the filters)

[signal,parameters] = decompose5(EMG, fs, badchan, padLen, initialization, NITER, nbextchan, silthr, covfilter, covthr, ...
    differentialmode, peeloff_flag, peeloffwin, duplicatesthresh, CoVDR, contrastfunc, refineMU, preproc_flag, DataFile.signal.recordedForce);

%% Save beside the loaded recording
[~,loadedBaseName] = fileparts(loadedFileName);
outputFile = fullfile(loadedFilePath, [loadedBaseName '-decomposed5.mat']);

if all(cellfun(@isempty,signal.Pulsetrain))
    warning('No motor units were found.');
end
save(outputFile,'signal','parameters','-v7.3');
fprintf('Saved decomposition to:\n%s\n',outputFile);
