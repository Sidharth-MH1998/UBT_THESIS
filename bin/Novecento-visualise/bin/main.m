whos Calib_data emgData fs badchan
size(emgData)
size(Calib_data.MUFilters)

cfg = struct;

cfg.activeInput       = 2;      % Novecento input number
cfg.onlineDurationSec = 30;     % decode for 30 seconds
cfg.windowBaseCols    = 64;     % 64 base cols = 256 samples at 2000 Hz
cfg.WiFi              = 0;      % 0 = ethernet/link-local, 1 = WiFi

cfg.calibChannels     = 1:128;   % offline channels used for calibration
cfg.emgChannels       = 1:128;   % online Novecento channels to decode

out = run_online_decomp_novecento_from_calib(Calib_data, recordedEMG, fs, badchan, cfg);