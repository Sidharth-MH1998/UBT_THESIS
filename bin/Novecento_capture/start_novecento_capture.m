% START_NOVECENTO_VISUAL_CAPTURE
% -------------------------------------------------------------------------
% Launches the simple Novecento live visualisation pipeline.

%% Inputs to stream
cfg = struct();
cfg.activeInputs = [1];
cfg.emgChannels = 1:64;

%% Live preview settings
cfg.previewChannels = 1:4:64;
cfg.blockDurationSec = 1;
cfg.visibleWindowSec = 15;

%% Hardware channel geometry
cfg.forceInputChannelCounts = [64 64 0 0 0 0 0 0 0 0];

%% Start capture
novecento_online(cfg);
