% START_REALTIME_NOVECENTO_SESSION
% -------------------------------------------------------------------------
% Required in workspace:
%   Calib_data
%   recordedEMG or EMG
%   fs
%   badchan

assert(exist('Calib_data', 'var') == 1, 'Calib_data not found in workspace.');
if exist('recordedEMG', 'var') ~= 1 && exist('trimmedEMG', 'var') == 1
    recordedEMG = trimmedEMG;
end
assert(exist('recordedEMG', 'var') == 1, 'recordedEMG/EMG not found in workspace.');
assert(exist('fs', 'var') == 1, 'fs not found in workspace.');

if exist('badchan', 'var') ~= 1
    badchan = [];
end

cfg = struct();
cfg.activeInputs = [1];
cfg.WiFi = 0;
cfg.calibChannels = 1:64;
% Each 64-electrode Novecento probe streams 70 rows:
% 64 electrode rows followed by 6 IMU/accessory rows.
cfg.emgChannels = [1:64]  ;%[1:64 71:134];
cfg.windowBaseCols = 64;
cfg.visibleWindowSec = 10;
cfg.onlineDurationSec = inf;
cfg.recordEMG = true;
cfg.printEveryNWindows = 10;
cfg.frYLim = 60;
cfg.forceInputChannelCounts = [70 70 0 0 0 0 0 0 0 0];
cfg.HRES = zeros(10, 1);
cfg.HRES(cfg.activeInputs) = 1;
cfg.FsampCode = zeros(10, 1);
cfg.FsampCode(cfg.activeInputs) = 1;

data_out = online_decomp(Calib_data, recordedEMG, fs, badchan, cfg);
