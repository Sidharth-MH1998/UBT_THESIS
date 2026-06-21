function out = run_online_decomp_novecento_from_calib(Calib_data, calibEMG_full, fs, badchan, userCfg)
% RUN_ONLINE_DECOMP_NOVECENTO_FROM_CALIB
% -------------------------------------------------------------------------
% Uses existing offline calibration (Calib_data.MUFilters) and performs
% online EMG decomposition from Novecento+ TCP streaming.
%
% INPUTS
%   Calib_data      : struct from decompose3/offline decomposition
%   calibEMG_full   : calibration EMG used offline (channels x samples)
%   fs              : sampling frequency used offline, e.g. 2000
%   badchan         : bad channels from offline decomposition
%   userCfg         : config struct
%
% REQUIRED FUNCTIONS ON PATH
%   getonlineparameters.m
%   getspikesonline.m
%
% NOTES
%   1) calibChannels and emgChannels must correspond to the SAME electrode
%      layout and same channel order.
%   2) badchan must refer to the SELECTED calibChannels/emgChannels, not
%      the full original 128 channels unless you selected all 128.
%   3) This code assumes one Novecento input is streamed online.

%% ---------------- DEFAULT CONFIG ----------------
cfg = default_cfg();
if nargin < 5
    userCfg = struct;
end
cfg = merge_structs(cfg, userCfg);

%% ---------------- VALIDATION ----------------
if nargin < 4 || isempty(badchan)
    badchan = [];
end

if nargin < 3 || isempty(fs)
    error('fs is required.');
end

if nargin < 2 || isempty(calibEMG_full)
    error('calibEMG_full is required.');
end

if nargin < 1 || isempty(Calib_data)
    error('Calib_data is required.');
end

if ~isfield(Calib_data, 'MUFilters') || isempty(Calib_data.MUFilters)
    error('Calib_data.MUFilters is missing or empty.');
end

if isempty(cfg.calibChannels)
    error('cfg.calibChannels must be specified.');
end

if isempty(cfg.emgChannels)
    error('cfg.emgChannels must be specified.');
end

if numel(cfg.calibChannels) ~= numel(cfg.emgChannels)
    error('cfg.calibChannels and cfg.emgChannels must have the same length.');
end

% Select calibration channels
if size(calibEMG_full,1) == numel(cfg.calibChannels)
    calibEMG = calibEMG_full;
elseif size(calibEMG_full,1) >= max(cfg.calibChannels)
    calibEMG = calibEMG_full(cfg.calibChannels, :);
else
    error('calibEMG_full does not contain the requested cfg.calibChannels.');
end

nCalibChan = size(calibEMG,1);

% Build EMG mask from selected channels
EMGmask = zeros(nCalibChan,1);
if ~isempty(badchan)
    if max(badchan) > nCalibChan
        error('badchan contains indices outside the selected calibration channels.');
    end
    EMGmask(badchan) = 1;
end

MUFilters = Calib_data.MUFilters;

fprintf('\n=== Preparing online parameters from offline calibration ===\n');
fprintf('Selected calibration channels: %d\n', nCalibChan);
fprintf('Bad channels: %d\n', sum(EMGmask));
fprintf('Number of MUs in Calib_data.MUFilters: %d\n', size(MUFilters,2));

% Recompute online parameters from calibration EMG + MUFilters
[extensionfactor, iReSIG, normval, centroid] = ...
    getonlineparameters(calibEMG, EMGmask, MUFilters, fs);

fprintf('Computed online parameters successfully.\n');

%% ---------------- CONNECT TO NOVECENTO ----------------
dev = novecento_connect(cfg);
cleanupObj = onCleanup(@() novecento_disconnect(dev)); %#ok<NASGU>

fprintf('\n=== Connected to Novecento+ ===\n');
fprintf('IP: %s\n', dev.ip);
fprintf('Active input: %d\n', cfg.activeInput);
fprintf('Detected channels on active input: %d\n', dev.NumChan(cfg.activeInput));
fprintf('Sampling rate on active input: %d Hz\n', dev.fsInput(cfg.activeInput));

if max(cfg.emgChannels) > dev.NumChan(cfg.activeInput)
    error('cfg.emgChannels exceeds detected channels on Novecento input %d.', cfg.activeInput);
end

fs_online = dev.fsInput(cfg.activeInput);
if fs_online ~= fs
    warning('Offline fs = %d but online Novecento fs = %d. This may break decoding.', fs, fs_online);
end

nsamp = fs_online * cfg.windowBaseCols / 500;
if mod(nsamp,1) ~= 0
    error('cfg.windowBaseCols gives a non-integer sample count. Choose a valid value.');
end
nsamp = round(nsamp);

windowSec = nsamp / fs_online;
nWin = floor(cfg.onlineDurationSec / windowSec);

fprintf('Online window: %d samples (%.3f s)\n', nsamp, windowSec);
fprintf('Number of windows: %d\n', nWin);

%% ---------------- ONLINE DECODING SETUP ----------------
nMU = size(MUFilters,2);
nGood = sum(EMGmask == 0);

MUfilt = MUFilters' * iReSIG;
esample2 = zeros(nGood * extensionfactor, extensionfactor - 1);

noise_centroids = ones(nsamp, nMU) .* (centroid(:,1)');
spike_centroids = ones(nsamp, nMU) .* (centroid(:,2)');

Pulsetrain = zeros(nMU, nWin * nsamp);
Distime    = zeros(nWin * nsamp, nMU);
EMG_online = zeros(numel(cfg.emgChannels), nWin * nsamp);

fprintf('\n=== Starting online decomposition ===\n');

try
    flush(dev.tcpSocket);
catch
end

pause(0.2);

%% ---------------- ONLINE LOOP ----------------
t0 = tic;

for k = 1:nWin
    blockAll = novecento_read_input_window(dev, cfg.activeInput, cfg.windowBaseCols, cfg.GainFactor);

    % Select same channel arrangement as offline calibration
    emgBlock = blockAll(cfg.emgChannels, :);

    idx = (k-1)*nsamp + (1:nsamp);
    EMG_online(:, idx) = emgBlock;

    emgGood = emgBlock(EMGmask == 0, :);

    [Pulsetrain(:, idx), Distime(idx, :), esample2] = ...
        getspikesonline(emgGood, extensionfactor, esample2, MUfilt, ...
                        normval, noise_centroids, spike_centroids, nsamp, fs_online);

    spikesThisWin = sum(Distime(idx,:) > 0, 1);
    fprintf('Window %3d / %3d | spikes per MU = %s\n', k, nWin, mat2str(spikesThisWin));
end

elapsed = toc(t0);

%% ---------------- FORMAT OUTPUT ----------------
Dischargetimes_online = distime_to_cell(Distime);
Time = (0:size(Pulsetrain,2)-1) / fs_online;

DR_online = nan(1,nMU);
for mu = 1:nMU
    if numel(Dischargetimes_online{mu}) >= 2
        isi = diff(Dischargetimes_online{mu}) / fs_online;
        DR_online(mu) = mean(1 ./ isi);
    end
end

%% ---------------- QUICK PLOT ----------------
figure('Name','Novecento Online Decomposition');
hold on
for mu = 1:nMU
    yoff = 2 * mu;
    plot(Time, Pulsetrain(mu,:) + yoff, 'LineWidth', 1.0);
    if ~isempty(Dischargetimes_online{mu})
        plot(Time(Dischargetimes_online{mu}), ...
             Pulsetrain(mu,Dischargetimes_online{mu}) + yoff, ...
             'o', 'MarkerSize', 4);
    end
end
xlabel('Time (s)');
title('Online Motor Unit Pulse Trains');
set(gca,'YTick',[]);
box on

%% ---------------- OUTPUT STRUCT ----------------
out = struct();
out.cfg = cfg;
out.fs = fs_online;
out.nsamp = nsamp;
out.windowSec = windowSec;
out.nWin = nWin;
out.elapsedSec = elapsed;

out.calibration = struct();
out.calibration.MUFilters = MUFilters;
out.calibration.EMGmask = EMGmask;
out.calibration.extensionfactor = extensionfactor;
out.calibration.iReSIG = iReSIG;
out.calibration.norm = normval;
out.calibration.centroid = centroid;

out.online = struct();
out.online.EMG = EMG_online;
out.online.Pulsetrain = Pulsetrain;
out.online.Distime = Distime;
out.online.Dischargetimes = Dischargetimes_online;
out.online.DR = DR_online;
out.online.Time = Time;

out.novecento = rmfield(dev, 'tcpSocket');

fprintf('\n=== Finished ===\n');
fprintf('Elapsed time: %.2f s\n', elapsed);

end

%% =========================================================================
function cfg = default_cfg()

cfg = struct();

% Network
cfg.WiFi    = 0;
cfg.TCPPort = 23456;
cfg.IP_eth  = '169.254.1.10';
cfg.IP_wifi = '192.168.1.1';

% Which Novecento input carries the EMG grid
cfg.activeInput = 1;

% Which channels in the OFFLINE calibration EMG correspond to online stream
cfg.calibChannels = 1:128;

% Which channels from the Novecento input are used online
cfg.emgChannels   = 1:128;

% Online stream duration
cfg.onlineDurationSec = 20;

% Window size in Novecento base columns
% 64 base cols at 2000 Hz => 256 samples => 128 ms
cfg.windowBaseCols = 64;

% Conversion factor to mV
cfg.GainFactor = 0.2861;

% Novecento config
cfg.FSelAux       = 2;
cfg.AnOutINSource = 0;
cfg.AnOutChan     = 1;
cfg.AnOutGain     = bin2dec('00000000');

% Input arrays for 10 Novecento inputs
cfg.IN_Active = zeros(10,1);
cfg.Mode      = zeros(10,1);
cfg.Gain      = zeros(10,1);
cfg.HRES      = zeros(10,1);
cfg.HPF       = zeros(10,1);
cfg.FsampCode = zeros(10,1);

% Default active input settings
cfg.IN_Active(1) = 1;
cfg.Mode(1)      = 0;
cfg.Gain(1)      = 1;
cfg.HRES(1)      = 1;
cfg.HPF(1)       = 1;
cfg.FsampCode(1) = 1;  % 2000 Hz

end

%% =========================================================================
function S = merge_structs(S, U)
if isempty(U), return; end
f = fieldnames(U);
for i = 1:numel(f)
    S.(f{i}) = U.(f{i});
end
end

%% =========================================================================
function dev = novecento_connect(cfg)

AuxFsamp = [0 16 32 48];
FsampVal = [500 2000 4000 8000];
SizeAux  = [16 64 128 256];
ChVsType = [0 14 22 38 46 70 102 0 0 0 0 0 0 0 0 0];

% Make sure selected active input is enabled
cfg.IN_Active(:) = 0;
cfg.Mode(:)      = 0 + cfg.Mode(:);
cfg.Gain(:)      = 0 + cfg.Gain(:);
cfg.HRES(:)      = 0 + cfg.HRES(:);
cfg.HPF(:)       = 0 + cfg.HPF(:);
cfg.FsampCode(:) = 0 + cfg.FsampCode(:);

cfg.IN_Active(cfg.activeInput) = 1;

% If user chose activeInput other than 1 and did not fill settings there,
% copy settings from input 1
if cfg.activeInput ~= 1
    cfg.Mode(cfg.activeInput)      = cfg.Mode(1);
    cfg.Gain(cfg.activeInput)      = cfg.Gain(1);
    cfg.HRES(cfg.activeInput)      = cfg.HRES(1);
    cfg.HPF(cfg.activeInput)       = cfg.HPF(1);
    cfg.FsampCode(cfg.activeInput) = cfg.FsampCode(1);
end

% Build config string
ConfString = zeros(1,15,'uint8');

ConfString(1) = uint8(bin2dec('10000000') + ...
                      AuxFsamp(cfg.FSelAux) + ...
                      cfg.IN_Active(10)*2 + cfg.IN_Active(9));

ConfString(2) = uint8(0);
for i = 1:8
    ConfString(2) = uint8(double(ConfString(2)) + cfg.IN_Active(i)*(2^(i-1)));
end

ConfString(3) = uint8(cfg.AnOutGain + cfg.AnOutINSource);
ConfString(4) = uint8(cfg.AnOutChan);

for i = 1:10
    ConfString(4+i) = uint8(cfg.Mode(i)*64 + cfg.Gain(i)*16 + ...
                            cfg.HPF(i)*8 + cfg.HRES(i)*4 + cfg.FsampCode(i));
end

ConfString(15) = uint8(novecento_crc8(double(ConfString), 14));

% Open TCP socket
if cfg.WiFi == 1
    ip = cfg.IP_wifi;
else
    ip = cfg.IP_eth;
end

tcpSocket = tcpclient(ip, cfg.TCPPort);
tcpSocket.ByteOrder = "little-endian";
tcpSocket.Timeout = 30;

disp('Connected to the socket');

% Firmware version request
cmd = uint8([2 0]);
cmd(2) = uint8(novecento_crc8(double(cmd(1)),1));
write(tcpSocket, cmd, 'uint8');
fw = read(tcpSocket, 20, 'uint8')';
disp('Firmware info:');
disp(char(fw(2:end)));

% Battery request
cmd = uint8([3 0]);
cmd(2) = uint8(novecento_crc8(double(cmd(1)),1));
write(tcpSocket, cmd, 'uint8');
bat = read(tcpSocket, 20, 'uint8')';
fprintf('Battery level: %d%%\n', bat(2));

% Hardware config request
cmd = uint8([1 0]);
cmd(2) = uint8(novecento_crc8(double(cmd(1)),1));
write(tcpSocket, cmd, 'uint8');

Settings = read(tcpSocket, 20, 'uint8')';
if numel(Settings) ~= 20
    error('Hardware settings read failed.');
end

if Settings(20) == 0
    disp('Hardware config request: no error');
elseif Settings(20) == 255
    error('Hardware config request returned CRC error.');
else
    fprintf('Hardware config request returned code: %d\n', Settings(20));
end

disp('Probe types per input:');
disp(Settings(2:11));

pause(0.2);

% Send configuration
write(tcpSocket, ConfString, 'uint8');

NumChan = zeros(10,1);
Ptr_IN  = zeros(11,1);
Size_IN = zeros(11,1);
Ptr_IN(1) = 1;
NumActInputs = 0;

for i = 1:10
    probeType = double(Settings(i+1));
    NumChan(i) = ChVsType(probeType + 1);

    if NumChan(i) == 0
        cfg.IN_Active(i) = 0;
    end

    if cfg.IN_Active(i) == 1
        Size_IN(i) = (cfg.HRES(i)+1) * FsampVal(cfg.FsampCode(i)+1) / 500 * NumChan(i);
        NumActInputs = NumActInputs + 1;
    else
        Size_IN(i) = 0;
    end

    Ptr_IN(i+1) = Ptr_IN(i) + Size_IN(i);
end

PacketSize1Block = Ptr_IN(11)-1 + SizeAux(cfg.FSelAux) + 128;

try
    tcpSocket.InputBufferSize = max(PacketSize1Block * 500 * 4, 1e6);
catch
end

fsInput = zeros(10,1);
for i = 1:10
    if cfg.IN_Active(i) == 1
        fsInput(i) = FsampVal(cfg.FsampCode(i)+1);
    end
end

dev = struct();
dev.ip = ip;
dev.tcpSocket = tcpSocket;
dev.cfg = cfg;
dev.Settings = Settings;
dev.ConfString = ConfString;
dev.PacketSize1Block = PacketSize1Block;
dev.NumChan = NumChan;
dev.Ptr_IN = Ptr_IN;
dev.Size_IN = Size_IN;
dev.NumActInputs = NumActInputs;
dev.fsInput = fsInput;

end

%% =========================================================================
function EMG = novecento_read_input_window(dev, inputIdx, nBaseCols, gainFactor)
% Reads one block from one Novecento input
%
% Output EMG:
%   channels x samples

cfg = dev.cfg;
fsInput = dev.fsInput(inputIdx);
numCh = dev.NumChan(inputIdx);

if cfg.IN_Active(inputIdx) ~= 1
    error('Requested input %d is not active.', inputIdx);
end

nRead = dev.PacketSize1Block * nBaseCols;

Temp = read(dev.tcpSocket, nRead, 'int16')';

if numel(Temp) ~= nRead
    error('Short read from Novecento. Expected %d int16 values, got %d.', nRead, numel(Temp));
end

Data = reshape(Temp, dev.PacketSize1Block, nBaseCols);

if cfg.HRES(inputIdx) == 0
    temp1 = reshape(Data(dev.Ptr_IN(inputIdx):dev.Ptr_IN(inputIdx+1)-1, :), 1, []);
    EMG = gainFactor * double(reshape(temp1, numCh, fsInput * nBaseCols / 500));
else
    temp1 = reshape(Data(dev.Ptr_IN(inputIdx):dev.Ptr_IN(inputIdx+1)-1, :), 1, []);
    temp2 = typecast(temp1, 'int32');
    EMG = gainFactor * double(reshape(temp2, numCh, fsInput * nBaseCols / 500));
end

end

%% =========================================================================
function novecento_disconnect(dev)

try
    stopString = dev.ConfString;
    stopString(1) = uint8(bin2dec('00000000'));
    stopString(15) = uint8(novecento_crc8(double(stopString), 14));
    write(dev.tcpSocket, stopString, 'uint8');
    pause(0.5);
catch
end

try
    clear dev.tcpSocket
catch
end

disp('Novecento connection closed.');

end

%% =========================================================================
function Dischargetimes = distime_to_cell(Distime)
Dischargetimes = cell(1, size(Distime,2));
for mu = 1:size(Distime,2)
    Dischargetimes{mu} = find(Distime(:,mu) > 0)';
end
end

%% =========================================================================
function crc = novecento_crc8(Vector, Len)

crc = 0;
j = 1;

while (Len > 0)
    Extract = Vector(j);
    for i = 8:-1:1 %#ok<NASGU>

        Sum = xor(mod(crc,2), mod(Extract,2));
        crc = floor(crc/2);

        if (Sum > 0)
            str = zeros(1,8);
            a = dec2bin(crc,8);
            b = dec2bin(140,8);
            for k = 1:8
                str(k) = ~((a(k) == b(k)));
            end
            crc = bin2dec(strrep(num2str(str),' ',''));
        end

        Extract = floor(Extract/2);
    end

    Len = Len - 1;
    j = j + 1;
end

end