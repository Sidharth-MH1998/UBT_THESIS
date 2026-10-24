
%% Start V2 online decomposition with the Arduino force stream
clear;
close all;

%% Select a decomposed or manually edited MUedit MAT file.
[matFileName, matFolder] = uigetfile('*.mat','Select decomposed MUedit file');
if isequal(matFileName, 0)
    disp('No MUedit file selected. Online decomposition cancelled.');
    return;
end

matFile = fullfile(matFolder, matFileName);
load(matFile);

calibration_data = signal;

% used manually edited pulse train if available
if exist('edition', 'var')
    editedMUFields = {'Pulsetrain', 'Dischargetimes'};
    for fieldIdx = 1:numel(editedMUFields)
        fieldName = editedMUFields{fieldIdx};
        if isfield(edition, fieldName)
            calibration_data.(fieldName) = edition.(fieldName);
        end
    end
    disp('Using manually edited decomposition data.');
else
    disp('Using non-edited decomposition data.');
end
fprintf('Loaded Calibration file: %s\n', matFile);

%% User settings
cfg = struct();

% Connection
cfg.WiFi = 0; % 0 = Ethernet, 1 = Wi-Fi
cfg.TCPPort = 23456;
cfg.IP_eth = '169.254.1.10';
cfg.IP_wifi = '192.168.1.1';

% Channel selection
cfg.activeInputs = 1;
cfg.calibChannels = 1:64; % channels from offline decomposition
cfg.emgChannels = 1:64; % online stream channels
cfg.forceInputChannelCounts = [70 0 0 0 0 0 0 0 0 0];

% Streaming and display
cfg.windowBaseCols = 64;
cfg.visibleWindowSec = 10;
cfg.onlineDurationSec = inf; % recording duration
cfg.recordEMG = true; % save EMG toggle
cfg.printEveryNWindows = 10;
cfg.showLegend = true;
cfg.frYLim = 60; % ylimit for firing rate
cfg.queryMetadata = false;

% I-Spin-style quadrant feedback (two selected motor units)
cfg.showQuadrant = true;
cfg.quadrantXMU = 1;
cfg.quadrantYMU = 2;
cfg.quadrantRateWindowSec = 1.0; % spike-count window used for pps
cfg.quadrantSmoothingWindows = 4; % moving average of displayed rates
cfg.quadrantHistorySec = 7.5; % visible cursor trail
cfg.quadrantAxisMax = []; % [] expands automatically, starting at 30 pps

% Communication reliability
cfg.socketTimeoutSec = 100;
cfg.hardwareQueryRetries = 3;
cfg.hardwareQueryPauseSec = 0.2;

% Novecento conversion, auxiliary input, and analog output
cfg.GainFactor = 0.2861;
cfg.FSelAux = 2;
cfg.AnOutINSource = 0;
cfg.AnOutChan = 1;
cfg.AnOutGain = bin2dec('00000000');

% Per-input acquisition settings
cfg.IN_Active = zeros(10,1);
cfg.Mode = zeros(10,1);
cfg.Gain = zeros(10,1);
cfg.HRES = zeros(10,1);
cfg.HPF = zeros(10,1);
cfg.FsampCode = zeros(10,1);

cfg.IN_Active(cfg.activeInputs) = 1;
cfg.Mode(cfg.activeInputs) = 0;
cfg.Gain(cfg.activeInputs) = 1;
cfg.HRES(cfg.activeInputs) = 0; % standard 16-bit resolution
cfg.HPF(cfg.activeInputs) = 1;
cfg.FsampCode(cfg.activeInputs) = 1; % 1 = 2000 Hz

% Arduino force stream
cfg.forcePort = 'COM3';
cfg.forceFs = 50;
cfg.forceMaxDurationSec = 10*60;
cfg.forceDisplayTimeSec = 15;
cfg.forceBufferTimeSec = 5;
cfg.forcePlotRateHz = 10;
cfg.forceCalibrationFile = '';
cfg.forcePromptCalibration = true;
cfg.forceDefaultCalibrationFactors = [10 10 10];
cfg.forceDefaultZeroValues = [0 0 0];
cfg.forceDefaultReverseStates = [false false false];

%% Run V2 decomposition and force acquisition together
data_out = online_decompositionV3(calibration_data,parameters,cfg);
