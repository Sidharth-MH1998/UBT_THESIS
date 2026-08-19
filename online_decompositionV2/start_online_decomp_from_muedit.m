%% Start online decomposition directly from signal and parameters

% Before running, load a MUedit MAT file containing signal and parameters.
% The required project folders must already be on the MATLAB path.
assert(exist('signal','var') == 1, ...
    'signal is not loaded in the workspace.');
assert(exist('parameters','var') == 1, ...
    'parameters is not loaded in the workspace.');

%% User settings
cfg = struct();

% Connection
cfg.WiFi = 0; % 0 = Ethernet, 1 = Wi-Fi
cfg.TCPPort = 23456;
cfg.IP_eth = '169.254.1.10';
cfg.IP_wifi = '192.168.1.1';

% Channel selection
cfg.activeInputs = [1];
cfg.calibChannels = 1:64; % channels from offline decomposition
cfg.emgChannels = [1:64]; % 71:134]; % online stream channels
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

%% Run the direct signal/parameters online pipeline
data_out = online_decomp_signal(signal,parameters,cfg);
