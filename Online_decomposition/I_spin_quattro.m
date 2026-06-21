%% =========================================================
%  Quattrocento Recording Script
%  Extracted from ISpin_Quattrocento_exported (standalone version)
%
%  Covers:
%    1. Configuration & Initialisation
%    2. Check Noise
%    3. Check EMG Quality
%    4. Force Offset Measurement
%    5. MVC Recording
% =========================================================

%% -------------------------------------------------------
%  USER SETTINGS — edit these before running
% -------------------------------------------------------
savepath        = 'C:\Data\recordings\';   % folder to save .mat files
configFile      = [savepath 'config.mat']; % path to your config.mat

fsamp           = 2048;    % sampling frequency (Hz): 2048 | 5120 | 10240
refreshrate     = 32;      % display refresh rate (Hz)
highpass        = 100;     % HP filter cutoff (Hz): 10 | 100 | 200
lowpass         = 900;     % LP filter cutoff (Hz): 500 | 900 | 4400

array_displayed = 1;       % which electrode grid to display (e.g. 1, 2 ...)

% MVC parameters
mvc_duration    = 5;       % duration of each MVC effort (s)
mvc_rest        = 10;      % rest between MVC efforts (s)

%% -------------------------------------------------------
%  SECTION 1 — Load config & Initialise Connection
% -------------------------------------------------------

% Load the electrode configuration saved by Quattrodlg
file = load(configFile);

% Compute communication parameters
nsamp = floor(fsamp / refreshrate);   % samples per display frame

[nchannel, gridchannels] = getgridconfigQuattro(file.signal.ports, ...
                                                 file.signal.adapter);

% Build the 40-byte configuration bitstring for the Quattrocento
ConfString = bitseqquattro(fsamp, nchannel, highpass, lowpass);

% Open TCP connection to the Quattrocento
tcpSocket = tcpclient('169.254.1.10', 23456);
tcpSocket.InputBufferSize = 2 * nchannel * fsamp;

% Identify grids (exclude aux channels 0 and 7)
grids   = unique(gridchannels);
grids   = setdiff(grids, [0 7]);
ngrid   = length(grids);
Muscles = file.signal.muscle;

fprintf('Initialisation complete. %d grids detected.\n', ngrid);

%% -------------------------------------------------------
%  SECTION 2 — Check Noise (15 s recording at rest)
% -------------------------------------------------------
fprintf('\n--- CHECK NOISE ---\n');

nwin        = floor((15 * fsamp) / nsamp);
nwinbuffmax = floor(fsamp * 5 / nsamp);
i           = 1;
nwinbuff    = 1;

% Pre-allocate
time   = linspace(0, 5, 5 * fsamp);
buffer = zeros(5 * fsamp, 64);
EMG    = zeros(sum(gridchannels(:) < 7 & gridchannels(:) > 0), nwin * nsamp);
offset = ones(64, nsamp) .* (1:64)';

% Plot setup
figure('Name','Check Noise');
hPlot = plot(time, buffer);
hold on;
hLine = line([time(nwinbuff*nsamp) time(nwinbuff*nsamp)], [0 64], ...
             'LineWidth', 1, 'Color', [0.81 0.50 1.00]);
xlim([0 5]); ylim([0 66]);
xlabel('Time (s)'); ylabel('Channels');

% Start streaming
ConfString(1) = ConfString(1) + 1;
ConfString(40) = CRC8(ConfString, 39);
fopen(tcpSocket);
set(tcpSocket, 'ByteOrder', 'little-endian');
fwrite(tcpSocket, ConfString, 'uint8');

while i <= nwin
    data = fread(tcpSocket, [nchannel, nsamp], 'int16');

    % Store EMG from grid channels
    EMG(:, (i-1)*nsamp+1 : i*nsamp) = ...
        data(gridchannels < 7 & gridchannels > 0, :);

    % Update rolling display buffer
    buffer((nwinbuff-1)*nsamp+1 : nwinbuff*nsamp, ...
           1:sum(gridchannels(:) == array_displayed)) = ...
        (data(gridchannels == array_displayed, :) * 0.0005 + offset)';

    % Refresh plot
    for k = 1:length(hPlot)
        if k <= size(buffer, 2)
            hPlot(k).YData = buffer(:, k);
        end
    end
    hLine.XData = [time(nwinbuff*nsamp) time(nwinbuff*nsamp)];
    drawnow limitrate

    i = i + 1;
    if nwinbuff < nwinbuffmax
        nwinbuff = nwinbuff + 1;
    else
        nwinbuff = 1;
    end
end

% Stop streaming
ConfString(1) = ConfString(1) - 1;
ConfString(40) = CRC8(ConfString, 39);
fwrite(tcpSocket, ConfString, 'uint8');
fclose(tcpSocket);
flush(tcpSocket);

% Compute per-channel RMS noise
Noisecheck = zeros(size(EMG, 1), 1);
for j = 1:size(EMG, 1)
    Noisecheck(j) = rms(EMG(j, fsamp:end-fsamp) / 1000);
end

figure('Name','Noise per Channel');
bar(Noisecheck);
xlabel('Channels'); ylabel('RMS amplitude (mV)');
title('Baseline Noise per Channel');

fprintf('Noise check complete.\n');

%% -------------------------------------------------------
%  SECTION 3 — Check EMG Quality (30 s recording)
% -------------------------------------------------------
fprintf('\n--- CHECK EMG QUALITY ---\n');

nwin        = floor((30 * fsamp) / nsamp);
nwinbuffmax = floor(fsamp * 5 / nsamp);
i           = 1;
nwinbuff    = 1;

% Pre-allocate
time   = linspace(0, 5, 5 * fsamp);
buffer = zeros(5 * fsamp, 64);
EMG    = zeros(sum(gridchannels(:) < 7 & gridchannels(:) > 0), nwin * nsamp);
offset = ones(64, nsamp) .* (1:64)';

% Plot setup
figure('Name','Check EMG');
hPlot = plot(time, buffer);
hold on;
hLine = line([time(nwinbuff*nsamp) time(nwinbuff*nsamp)], [0 64], ...
             'LineWidth', 1, 'Color', [0.81 0.50 1.00]);
xlim([0 5]); ylim([0 66]);
xlabel('Time (s)'); ylabel('Channels');

% Start streaming
ConfString(1) = ConfString(1) + 1;
ConfString(40) = CRC8(ConfString, 39);
fopen(tcpSocket);
set(tcpSocket, 'ByteOrder', 'little-endian');
fwrite(tcpSocket, ConfString, 'uint8');

while i <= nwin
    data = fread(tcpSocket, [nchannel, nsamp], 'int16');

    EMG(:, (i-1)*nsamp+1 : i*nsamp) = ...
        data(gridchannels < 7 & gridchannels > 0, :);

    buffer((nwinbuff-1)*nsamp+1 : nwinbuff*nsamp, ...
           1:sum(gridchannels(:) == array_displayed)) = ...
        (data(gridchannels == array_displayed, :) * 0.0005 + offset)';

    for k = 1:length(hPlot)
        if k <= size(buffer, 2)
            hPlot(k).YData = buffer(:, k);
        end
    end
    hLine.XData = [time(nwinbuff*nsamp) time(nwinbuff*nsamp)];
    drawnow limitrate

    i = i + 1;
    if nwinbuff < nwinbuffmax
        nwinbuff = nwinbuff + 1;
    else
        nwinbuff = 1;
    end
end

% Stop streaming
ConfString(1) = ConfString(1) - 1;
ConfString(40) = CRC8(ConfString, 39);
fwrite(tcpSocket, ConfString, 'uint8');
fclose(tcpSocket);
flush(tcpSocket);

% Identify bad channels and electrode layout
[coordinates, IED, DiscardChannels, emgtype] = ...
    formatsignalHDEMG(EMG, file.signal.gridname, fsamp, 1);

% Save EMG checking file
DisChannels = DiscardChannels;
Musclename  = Muscles;
save([savepath 'EMGChecking ' replace(datestr(datetime('now')),':','_') '.mat'], ...
     'EMG', 'DisChannels', 'Musclename');

fprintf('EMG quality check complete. File saved.\n');

%% -------------------------------------------------------
%  SECTION 4 — Force Offset Measurement (3 s at rest)
% -------------------------------------------------------
fprintf('\n--- MEASURING FORCE OFFSET ---\n');

nwin     = floor((3 * fsamp) / nsamp);
i        = 1;
force    = zeros(1, nwin * nsamp);
forceidx = find(gridchannels == 7, 1, 'First');

% Start streaming
ConfString(1) = ConfString(1) + 1;
ConfString(40) = CRC8(ConfString, 39);
fopen(tcpSocket);
set(tcpSocket, 'ByteOrder', 'little-endian');
fwrite(tcpSocket, ConfString, 'uint8');

while i <= nwin
    data = fread(tcpSocket, [nchannel, nsamp], 'int16');
    force((i-1)*nsamp+1 : i*nsamp) = data(forceidx, :);
    i = i + 1;
end

% Stop streaming
ConfString(1) = ConfString(1) - 1;
ConfString(40) = CRC8(ConfString, 39);
fwrite(tcpSocket, ConfString, 'uint8');
fclose(tcpSocket);
flush(tcpSocket);

% Compute offset (skip first second for amplifier stabilisation)
offsetforce = mean(force(fsamp:end));
fprintf('Force offset: %.4f\n', offsetforce);

%% -------------------------------------------------------
%  SECTION 5 — MVC Recording (3 trials with rest)
% -------------------------------------------------------
fprintf('\n--- MVC RECORDING ---\n');

% Build timeline: 10 s prep, then 3 trials of [effort / rest / effort / rest / effort]
trialength = fsamp * mvc_duration * 3 + fsamp * mvc_rest * 2 + fsamp * 10;
nwin       = floor(trialength / nsamp);
i          = 1;

% LED / colour indicator vectors
MVCBeg   = zeros(fsamp * 10, 1);
MVCtrial = ones(fsamp * mvc_duration, 1);
MVCrest  = zeros(fsamp * mvc_rest, 1);
MVClight = [MVCBeg; MVCtrial; MVCrest; MVCtrial; MVCrest; MVCtrial];

% Countdown timers for display
TimeBeg   = linspace(10, 0, 10 * fsamp);
Timetrial = zeros(1, fsamp * mvc_duration);
Timerest  = linspace(mvc_rest, 0, mvc_rest * fsamp);
Time      = [TimeBeg, Timetrial, Timerest, Timetrial, Timerest, Timetrial];

% Pre-allocate
EMG      = zeros(sum(gridchannels(:) < 7 & gridchannels(:) > 0), trialength);
Force    = zeros(1, trialength);
forceidx = find(gridchannels == 7, 1, 'First');

% Plot setup
figure('Name','MVC Recording');
hGauge = uicontrol('Style','text','Position',[10 10 200 30], ...
                   'String','Force: 0','FontSize',14);

% Start streaming
ConfString(1) = ConfString(1) + 1;
ConfString(40) = CRC8(ConfString, 39);
fopen(tcpSocket);
set(tcpSocket, 'ByteOrder', 'little-endian');
fwrite(tcpSocket, ConfString, 'uint8');

while i <= nwin
    data = fread(tcpSocket, [nchannel, nsamp], 'int16');

    EMG(:, (i-1)*nsamp+1 : i*nsamp) = ...
        data(gridchannels < 7 & gridchannels > 0, :);

    Force((i-1)*nsamp+1 : i*nsamp) = data(forceidx, :) - offsetforce;

    % Display current force and countdown
    currentForce = abs(mean(Force((i-1)*nsamp+1 : i*nsamp))) * 0.0005;
    countdown    = Time(i * nsamp);

    if MVClight(i * nsamp) == 1
        phase = 'CONTRACT';
    else
        phase = 'REST';
    end
    fprintf('Phase: %s | Countdown: %.1f s | Force: %.4f\n', ...
            phase, countdown, currentForce);

    drawnow
    i = i + 1;
end

% Stop streaming
ConfString(1) = ConfString(1) - 1;
ConfString(40) = CRC8(ConfString, 39);
fwrite(tcpSocket, ConfString, 'uint8');
fclose(tcpSocket);
flush(tcpSocket);

% Remove first second (amplifier initialisation artefact)
EMG   = EMG(:, fsamp:end);
Force = Force(fsamp:end);

% Estimate MVC using 250 ms moving average
MVC = max(abs(movmean(Force, fsamp * 0.25)));
fprintf('MVC = %.2f\n', MVC);

% Save MVC file
MVCforce     = MVC;
Offset_force = offsetforce;
DisChannels  = DiscardChannels;
Musclename   = Muscles;
save([savepath 'MVC ' replace(datestr(datetime('now')),':','_') '.mat'], ...
     'EMG', 'MVCforce', 'Force', 'Offset_force', 'Time', 'MVClight', ...
     'DisChannels', 'Musclename');

fprintf('MVC recording complete. File saved.\n');

%% -------------------------------------------------------
%  SECTION 6 — Stop / Clean Up
% -------------------------------------------------------
% Send stop command and close socket cleanly
ConfString(1) = bin2dec('10000000');
ConfString(40) = CRC8(ConfString, 39);
fwrite(tcpSocket, ConfString, 'uint8');
fclose(tcpSocket);
flush(tcpSocket);
clear tcpSocket;

fprintf('\nRecording session complete. All files saved to: %s\n', savepath);