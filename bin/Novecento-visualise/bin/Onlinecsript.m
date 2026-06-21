% =========================================================================
% TRULY ONLINE EMG DECOMPOSITION — Novecento+ + getspikesonline
% OT Bioelettronica TCP stream → real-time motor unit discharge times
%
% REQUIREMENTS before running:
%   1. Calib_data.MUFilters in workspace  (from offline decomposition)
%   2. recordedEMG in workspace           (calibration signal)
%   3. getonlineparameters.m in path
%   4. getspikesonline.m in path
%   5. CRC8.m in path
%   6. Novecento+ powered on and connected via Ethernet
% =========================================================================

close all

% =========================================================================
% SECTION 1: DECOMPOSITION PARAMETERS
% =========================================================================

fs             = 2000;
window_sec     = 0.125;
window_samples = round(window_sec * fs);   % 250 samples
badchan        = [];

% =========================================================================
% SECTION 2: VALIDATE CALIBRATION INPUTS
% =========================================================================

assert(exist('recordedEMG','var')==1, ...
    'recordedEMG not found in workspace. Run calibration first.')
assert(exist('Calib_data','var')==1, ...
    'Calib_data not found in workspace. Run decompose3() first.')

fprintf('\n=== Online EMG Decomposition — Novecento+ ===\n')

% =========================================================================
% SECTION 3: BUILD CHANNEL MASK
% =========================================================================

EMGmask          = zeros(size(recordedEMG,1), 1);
EMGmask(badchan) = 1;
nGoodChan        = sum(EMGmask == 0);

fprintf('Channels: %d total | %d good | %d excluded\n\n', ...
    size(recordedEMG,1), nGoodChan, numel(badchan))

% =========================================================================
% SECTION 4: LOAD CALIBRATION FILTERS
% =========================================================================

MUFilters = Calib_data.MUFilters;
nMUs      = size(MUFilters, 2);

if nMUs == 0
    error('No MU filters found in Calib_data.')
end

fprintf('Calibration: %d MUs loaded\n\n', nMUs)

% =========================================================================
% SECTION 5: COMPUTE ONLINE PARAMETERS
% =========================================================================

fprintf('Computing online parameters...\n')
[extensionfactor, iReSIG, norm, centroid] = getonlineparameters(recordedEMG, EMGmask, MUFilters, fs);

% Precompute combined filter — only done once outside loop
MUfilt = MUFilters' * iReSIG;   % nMUs x nExtChan

% Centroid matrices at window size
noise_centroids = ones(window_samples, nMUs) .* (centroid(:,1)');
spike_centroids = ones(window_samples, nMUs) .* (centroid(:,2)');

fprintf('Online parameters ready.\n\n')

% =========================================================================
% SECTION 6: NOVECENTO+ CONNECTION PARAMETERS
% =========================================================================

WiFi   = 0;
offset = 500;

IN_Active = zeros(10,1);
Mode      = zeros(10,1);
Gain      = zeros(10,1);
HRES      = zeros(10,1);
HPF       = zeros(10,1);
Fsamp     = zeros(10,1);
NumChan   = zeros(10,1);
Ptr_IN    = zeros(11,1);
Size_IN   = zeros(11,1);

ChVsType = [0 14 22 38 46 70 102 0 0 0 0 0 0 0 0 0];

% Input 1 — 64ch array at 2000 Hz
IN_Active(1) = 1;
Mode(1)      = 0;
Gain(1)      = 1;
HRES(1)      = 1;
HPF(1)       = 1;
Fsamp(1)     = 1;   % code 1 = 2000 Hz

AuxFsamp = [0 16 32 48];
FsampVal = [500 2000 4000 8000];
SizeAux  = [16 64 128 256];
FSelAux  = 2;

AnOutINSource = 0;
AnOutChan     = 1;
AnOutGain     = bin2dec('00000000');

TCPPort    = 23456;
GainFactor = 0.2861;

% =========================================================================
% SECTION 7: BUILD CONFIG STRING
% =========================================================================

ConfString(1) = bin2dec('10000000') + AuxFsamp(FSelAux) + ...
                IN_Active(10)*2 + IN_Active(9);
ConfString(2) = 0;
for i = 1:8
    ConfString(2) = ConfString(2) + IN_Active(i)*(2^(i-1));
end
ConfString(3) = AnOutGain + AnOutINSource;
ConfString(4) = AnOutChan;
for i = 1:10
    ConfString(4+i) = Mode(i)*64 + Gain(i)*16 + HPF(i)*8 + HRES(i)*4 + Fsamp(i);
end
ConfString(15) = CRC8(ConfString, 14);

% =========================================================================
% SECTION 8: TCP CONNECTION
% =========================================================================

if WiFi == 1
    tcpScoket = tcpclient('192.168.1.1', TCPPort);
else
    tcpScoket = tcpclient('169.254.1.10', TCPPort);
end
tcpScoket.ByteOrder = "little-endian";
tcpScoket.Timeout   = 100;
disp('Connected to Novecento+')

% Firmware query
GetSetCmd(1) = 2;
GetSetCmd(2) = CRC8(GetSetCmd, 1);
write(tcpScoket, GetSetCmd, 'uint8');
Settings = read(tcpScoket, 20, 'uint8')';
char(Settings(2:end))

% Battery query
GetSetCmd(1) = 3;
GetSetCmd(2) = CRC8(GetSetCmd, 1);
write(tcpScoket, GetSetCmd, 'uint8');
Settings = read(tcpScoket, 20, 'uint8')';
sprintf('Battery Level: %d%%', Settings(2))

% Hardware query
GetSetCmd(1) = 1;
GetSetCmd(2) = CRC8(GetSetCmd, 1);
write(tcpScoket, GetSetCmd, 'uint8');
Settings = read(tcpScoket, 20, 'uint8')';

if Settings(20) == 0
    disp('Error None')
elseif Settings(20) == 255
    disp('Error CRC')
end

disp('Probes configuration:')
disp(Settings(2:11))
pause(0.2)

% Send config to device
write(tcpScoket, ConfString, 'uint8');

% =========================================================================
% SECTION 9: CALCULATE PACKET SIZE — FIXED FOR 0.125s WINDOW
% =========================================================================

NumActInputs = 0;
Ptr_IN(1)    = 1;
for i = 1:10
    NumChan(i) = ChVsType(Settings(i+1)+1);
    if NumChan(i) == 0
        IN_Active(i) = 0;
    end
    if IN_Active(i) == 1
        Size_IN(i)   = (HRES(i)+1) * FsampVal(Fsamp(i)+1)/500 * NumChan(i);
        NumActInputs = NumActInputs + 1;
    end
    Ptr_IN(i+1) = Ptr_IN(i) + Size_IN(i);
end

PacketSize1Block = Ptr_IN(11)-1 + SizeAux(FSelAux) + 128;

% KEY FIX: use actual fs instead of hardcoded 500
% nBaseSamples = how many 500Hz-equivalent samples in one window
% At 2000Hz, 0.125s = 250 samples
% The packet is structured in 500Hz blocks, so scale accordingly
nBaseSamples = round(FsampVal(Fsamp(1)+1) * window_sec);  % 2000*0.125 = 250
nReadSamples = PacketSize1Block * nBaseSamples / (FsampVal(Fsamp(1)+1)/500);

% Buffer size
blockData = PacketSize1Block * nBaseSamples * 2;
tcpScoket.InputBufferSize = blockData * 2;

fprintf('PacketSize1Block : %d\n', PacketSize1Block)
fprintf('nBaseSamples     : %d\n', nBaseSamples)
fprintf('nReadSamples     : %d\n', nReadSamples)

% =========================================================================
% SECTION 10: PREALLOCATE ONLINE OUTPUTS
% =========================================================================

recordedEMG           = [];
Pulsetrain_online     = zeros(nMUs, 0);
Dischargetimes_online = cell(1, nMUs);
fr_online             = cell(1, nMUs);
for mu = 1:nMUs
    Dischargetimes_online{mu} = [];
    fr_online{mu}             = [];
end

% Boundary samples between windows
esample2 = zeros(nGoodChan * extensionfactor, extensionfactor-1);

% Global sample counter
globalSample = 0;

% =========================================================================
% SECTION 11: SETUP LIVE FIGURE
% =========================================================================

colors = lines(nMUs);

fig = figure('Color','w', 'Position',[50 50 1400 800], ...
    'Name','Online Decomposition — Novecento+');

% Raster plot
ax_raster = subplot(2,1,1);
hold(ax_raster, 'on')
title(ax_raster, 'Live Spike Trains', 'FontSize', 11)
xlabel(ax_raster, 'Time (s)')
ylabel(ax_raster, 'Motor Unit')
ylim(ax_raster, [0 nMUs+1])
yticks(ax_raster, 1:nMUs)
yticklabels(ax_raster, arrayfun(@(x) sprintf('MU%d  (0 spikes)',x), ...
    1:nMUs, 'UniformOutput',false))
grid(ax_raster, 'on')

% Firing rate plot
ax_fr = subplot(2,1,2);
hold(ax_fr, 'on')
title(ax_fr, 'Instantaneous Firing Rate (Hz)', 'FontSize', 11)
xlabel(ax_fr, 'Time (s)')
ylabel(ax_fr, 'Firing Rate (Hz)')
ylim(ax_fr, [0 60])
grid(ax_fr, 'on')

% Plot handles
h_raster = gobjects(nMUs, 1);
for mu = 1:nMUs
    h_raster(mu) = plot(ax_raster, nan, nan, '|', ...
        'Color', colors(mu,:), 'MarkerSize',10, 'LineWidth',1.5);
end

h_fr = gobjects(nMUs, 1);
for mu = 1:nMUs
    h_fr(mu) = plot(ax_fr, nan, nan, '.', ...
        'Color', colors(mu,:), 'MarkerSize', 4, ...
        'DisplayName', sprintf('MU%d',mu));
end
legend(ax_fr, 'Location','eastoutside', 'FontSize', 6)

tline_raster = xline(ax_raster, 0, 'r--', 'LineWidth', 1.5);
tline_fr     = xline(ax_fr,     0, 'r--', 'LineWidth', 1.5);

fprintf('Recording started — press Ctrl+C to stop\n\n')

% =========================================================================
% SECTION 12: MAIN ONLINE LOOP
% =========================================================================

cycle = 1;

while true

    fprintf('Window %d | %.2f sec recorded\n', cycle, globalSample/fs)

    % --- Read exactly one window from TCP stream
    Temp = read(tcpScoket, nReadSamples, 'int16')';
    Data = reshape(Temp, PacketSize1Block, nBaseSamples);
    clear Temp

    % --- Extract Input 1 EMG
    for In = 1:10
        if IN_Active(In) == 1
            if HRES(In) == 0
                Temp1      = reshape(Data(Ptr_IN(In):Ptr_IN(In+1)-1, :), ...
                                1, NumChan(In)*nBaseSamples);
                Sig_IN{In} = GainFactor*(int32(reshape(Temp1, ...
                                NumChan(In), nBaseSamples)));
            else
                % HRES=1: two int16 per sample → typecast to int32
                Temp1      = reshape(Data(Ptr_IN(In):Ptr_IN(In+1)-1, :), ...
                                1, NumChan(In)*nBaseSamples*(HRES(In)+1));
                Temp2      = typecast(Temp1, 'int32');
                Sig_IN{In} = GainFactor*(int32(reshape(Temp2, ...
                                NumChan(In), nBaseSamples)));
                clear Temp2
            end
            clear Temp1

            % Accumulate raw EMG
            recordedEMG = [recordedEMG, Sig_IN{In}(1:64, :)];
        end
    end

    % --- Window indices in global timeline
    start_idx = globalSample + 1;
    end_idx   = globalSample + window_samples;

    % --- Extract good channels
    EMGtmp1 = double(Sig_IN{1}(1:64, :));
    EMGtmp2 = EMGtmp1(EMGmask==0, :);

    % --- Decompose this window
    [pt_window, dt_window, esample2] = getspikesonline( ...
        EMGtmp2, extensionfactor, esample2, ...
        MUfilt, norm, noise_centroids, ...
        spike_centroids, window_samples, fs);

    % Append pulse train
    Pulsetrain_online = [Pulsetrain_online, pt_window];

    % --- Accumulate discharge times and firing rates
    for mu = 1:nMUs
        new_spikes = find(dt_window(:, mu)) + start_idx - 1;
        if ~isempty(new_spikes)
            Dischargetimes_online{mu} = [Dischargetimes_online{mu}; new_spikes];
        end
        if length(Dischargetimes_online{mu}) > 1
            fr_online{mu} = 1 ./ (diff(Dischargetimes_online{mu}) / fs);
        end
    end

    % Update global counter
    globalSample = end_idx;
    current_time = globalSample / fs;

    % --- Update raster
    for mu = 1:nMUs
        if ~isempty(Dischargetimes_online{mu})
            spikes_t = Dischargetimes_online{mu} / fs;
            set(h_raster(mu), ...
                'XData', spikes_t, ...
                'YData', mu * ones(size(spikes_t)))
        end
    end

    % Scrolling x-axis — show last 30 seconds
    xlim(ax_raster, [max(0, current_time-30), current_time+5])
    xlim(ax_fr,     [max(0, current_time-30), current_time+5])

    % Live spike count labels
    yticklabels(ax_raster, arrayfun(@(mu) ...
        sprintf('MU%d  (%d spikes)', mu, length(Dischargetimes_online{mu})), ...
        1:nMUs, 'UniformOutput', false))

    % --- Update firing rate
    for mu = 1:nMUs
        if length(Dischargetimes_online{mu}) > 1
            spike_times_fr = Dischargetimes_online{mu}(1:end-1) / fs;
            set(h_fr(mu), ...
                'XData', spike_times_fr, ...
                'YData', fr_online{mu})
        end
    end

    % Advance time indicator
    set(tline_raster, 'Value', current_time)
    set(tline_fr,     'Value', current_time)

    title(ax_raster, sprintf('Live Spike Trains  |  t = %.2f sec  |  %d MUs', ...
        current_time, nMUs), 'FontSize', 10)

    drawnow limitrate

    cycle = cycle + 1;

end

% =========================================================================
% SECTION 13: AFTER Ctrl+C — run in command window
% =========================================================================
%
%   stopNovecento
%
%   mean_fr_online = zeros(nMUs,1);
%   for mu = 1:nMUs
%       if ~isempty(fr_online{mu})
%           mean_fr_online(mu) = mean(fr_online{mu});
%       end
%   end
%
%   filename = ['OnlineDecomp_' datestr(now,'yyyymmdd_HHMMSS') '.mat'];
%   save(filename, 'recordedEMG', 'Pulsetrain_online', ...
%        'Dischargetimes_online', 'fr_online', 'mean_fr_online')
%   fprintf('Saved to %s\n', filename)
%
% =========================================================================