function cfg = makeNovecentoConfig(blockDurationSec, activeInputs, emgChannels)
%MAKENOVECENTOCONFIG Build the Novecento streaming configuration.
%
% INPUTS
%   blockDurationSec - Duration of each EMG read block, in seconds.
%   activeInputs     - Physical Novecento inputs to enable.
%   emgChannels      - Stream-channel indices retained for recording.
%
% OUTPUT
%   cfg              - Novecento connection, input, filter, sampling,
%                      auxiliary, and analog-output configuration.
%
% Selected inputs use standard-resolution acquisition, gain code 1,
% high-pass-filter code 1, and sampling-frequency code 1 (2000 Hz).

    cfg = struct();

    % Streaming
    cfg.socketTimeoutSec = 100;
    cfg.activeInputs = activeInputs;
    cfg.emgChannels = emgChannels;
    cfg.blockDurationSec = blockDurationSec;
    cfg.GainFactor = 0.2861;

    % Hardware communication
    cfg.hardwareQueryRetries = 3;
    cfg.hardwareQueryPauseSec = 0.2;

    % Auxiliary and analog output
    cfg.FSelAux = 2;
    cfg.forceInputChannelCounts = [];
    cfg.AnOutINSource = 0;
    cfg.AnOutChan = 1;
    cfg.AnOutGain = bin2dec('00000000');

    % Per-input settings for ten available Novecento inputs
    cfg.IN_Active = zeros(10,1);
    cfg.Mode = zeros(10,1);
    cfg.Gain = zeros(10,1);
    cfg.HRES = zeros(10,1);
    cfg.HPF = zeros(10,1);
    cfg.FsampCode = zeros(10,1);

    % Configure selected inputs
    cfg.IN_Active(activeInputs) = 1;
    cfg.Gain(activeInputs) = 1;
    cfg.HRES(activeInputs) = 0;
    cfg.HPF(activeInputs) = 1;
    cfg.FsampCode(activeInputs) = 1;
end