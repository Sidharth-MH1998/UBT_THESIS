% Hardware-free preview of the recruitment recorder and trial saving.
% Run this script, then press Track Record or Record in the interface.
demoDir = fileparts(mfilename('fullpath'));
addpath(demoDir);
cfg = struct();
cfg.simulation = true;
cfg.recordEMG = true;
cfg.activeInputs = 1:2;
cfg.emgChannels = reshape((1:64).' + 70*(0:1),1,[]);
cfg.windowBaseCols = 64; % 128-ms blocks at the simulated 2000-Hz EMG rate
cfg.onlineDurationSec = inf;
cfg.forceMaxDurationSec = 5*60;
cfg.forceFs = 50;
cfg.forcePlotRateHz = 10;
cfg.visibleWindowSec = 10;
cfg.forceDisplayTimeSec = 15;
cfg.forceBufferTimeSec = 5;
cfg.forceCalibrationFile = '';
cfg.forcePromptCalibration = false;
cfg.forceDefaultCalibrationFactors = [10 10 10];
cfg.forceDefaultZeroValues = [0 0 0];
cfg.forceDefaultReverseStates = [false false false];
cfg.muEditGridName = {'GR08MM1305','GR08MM1305'};
cfg.muEditMuscle = {'simulated flexor','simulated extensor'};
cfg.outputFolder = fullfile(demoDir,'demo_recordings');
data_out = record_mu_recruitment([],[],cfg);
