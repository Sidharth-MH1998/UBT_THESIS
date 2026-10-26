%% streamEMGNovecento
% -------------------------------------------------------------------------
% read EMG data and plot from Novecento.
%   r = mark the start sample
%   q = mark the stop sample and create trimmedEMG
%   close figure = stop Novecento streaming safely
clear;
close all;

%% user config
cfg = struct();
cfg.socketTimeoutSec = 100;
cfg.activeInputs = [1]; %inputs
cfg.emgChannels = [1:64] ;  % 71:134]; %channel Config
cfg.previewChannels = 1:4:64;
cfg.blockDurationSec = 1;
cfg.visibleWindowSec = 15;

% Novecento conversion and packet geometry.
cfg.GainFactor = 0.2861;
cfg.FSelAux = 2;
cfg.forceInputChannelCounts = [];
% Hardware query.
cfg.hardwareQueryRetries = 3;
cfg.hardwareQueryPauseSec = 0.2;
% Analog output.
cfg.AnOutINSource = 0;
cfg.AnOutChan = 1;
cfg.AnOutGain = bin2dec('00000000');
cfg.IN_Active = zeros(10, 1);
cfg.Mode = zeros(10, 1);
cfg.Gain = zeros(10, 1);
cfg.HRES = zeros(10, 1);
cfg.HPF = zeros(10, 1);
cfg.FsampCode = zeros(10, 1);
% input config
cfg.IN_Active(cfg.activeInputs) = 1;
cfg.Gain(cfg.activeInputs) = 1;
cfg.HRES(cfg.activeInputs) = 1;
cfg.HPF(cfg.activeInputs) = 1;
cfg.FsampCode(cfg.activeInputs) = 1;

novecento_live_plot(cfg);

if exist('recordedEMG','var') && ~isempty(recordedEMG)

    FsampVal = [500 2000 4000 8000];
    fs_emg = FsampVal(cfg.FsampCode(cfg.activeInputs(1)) + 1);

    save('RecordedEMG.mat','recordedEMG','fs_emg','-v7.3');

else
    warning('No recorded EMG available. Press r and then q first.');
end