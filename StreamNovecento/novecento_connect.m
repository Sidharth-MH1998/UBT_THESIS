function dev = novecento_connect(cfg)
%NOVECENTO_CONNECT Open TCP connection and configure Novecento+ streaming.
% Connect and prepare the hardware for reading
% input : cfg containing the requested Novecento configuration
%output : dev containing the connected device and all information required to read EMG


ip = '169.254.1.10';
tcpPort = 23456;

AuxFsamp = [0 16 32 48];
FsampVal = [500 2000 4000 8000];
SizeAux = [16 64 128 256];
ChVsType = [0 14 22 38 46 70 102 0 0 0 0 0 0 0 0 0];

cfg = prepare_input_config(cfg);
confString = build_config_string(cfg, AuxFsamp);

tcpSocket = tcpclient(ip, tcpPort);
tcpSocket.ByteOrder = "little-endian";
tcpSocket.Timeout = cfg.socketTimeoutSec;

settings = request_hardware_settings(tcpSocket, cfg);
write(tcpSocket, confString, 'uint8');

[numChan, ptrIn, sizeIn, cfg] = build_packet_layout(settings, cfg, ChVsType, FsampVal);

packetSize = ptrIn(11) - 1 + SizeAux(cfg.FSelAux) + 128;
try
    tcpSocket.InputBufferSize = max(packetSize * 500 * 4, 1e6);
catch
end

fsInput = zeros(10, 1);
for inputIdx = 1:10
    if cfg.IN_Active(inputIdx) == 1
        fsInput(inputIdx) = FsampVal(cfg.FsampCode(inputIdx) + 1);
    end
end

dev = struct();
dev.ip = ip;
dev.tcpSocket = tcpSocket;  % live Novecento connection
dev.cfg = cfg; % final configuration
dev.Settings = settings;   % detected hardware/probe types 
dev.ConfString = confString;
dev.PacketSize1Block = packetSize;
dev.NumChan = numChan;
dev.Ptr_IN = ptrIn;  % start position of each input
dev.Size_IN = sizeIn; % data size of each input 
dev.fsInput = fsInput;  % sampling rate per input
 
end

function cfg = prepare_input_config(cfg)

cfg.IN_Active(:) = 0;
cfg.IN_Active(cfg.activeInputs) = 1;

for inputIdx = cfg.activeInputs(:)'
    if inputIdx ~= 1
        if cfg.Gain(inputIdx) == 0
            cfg.Gain(inputIdx) = cfg.Gain(1);
        end
        if cfg.HRES(inputIdx) == 0
            cfg.HRES(inputIdx) = cfg.HRES(1);
        end
        if cfg.HPF(inputIdx) == 0
            cfg.HPF(inputIdx) = cfg.HPF(1);
        end
        if cfg.FsampCode(inputIdx) == 0
            cfg.FsampCode(inputIdx) = cfg.FsampCode(1);
        end
    end
end

end

function confString = build_config_string(cfg, AuxFsamp)

confString = zeros(1, 15, 'uint8');
confString(1) = uint8(bin2dec('10000000') + AuxFsamp(cfg.FSelAux) + cfg.IN_Active(10) * 2 + cfg.IN_Active(9));

for inputIdx = 1:8
    confString(2) = uint8(double(confString(2)) + cfg.IN_Active(inputIdx) * 2^(inputIdx - 1));
end

confString(3) = uint8(cfg.AnOutGain + cfg.AnOutINSource);
confString(4) = uint8(cfg.AnOutChan);

for inputIdx = 1:10
    confString(4 + inputIdx) = uint8( ...
        cfg.Mode(inputIdx) * 64 + ...
        cfg.Gain(inputIdx) * 16 + ...
        cfg.HPF(inputIdx) * 8 + ...
        cfg.HRES(inputIdx) * 4 + ...
        cfg.FsampCode(inputIdx));
end

confString(15) = uint8(CRC8(double(confString), 14));

end

function settings = request_hardware_settings(tcpSocket, cfg)

settings = [];
lastReadError = [];

for attempt = 1:cfg.hardwareQueryRetries
    try
        flush(tcpSocket);
    catch
    end

    pause(cfg.hardwareQueryPauseSec);

    cmd = uint8([1 0]);
    cmd(2) = uint8(CRC8(double(cmd(1)), 1));
    write(tcpSocket, cmd, 'uint8');

    try
        settings = read(tcpSocket, 20, 'uint8')';
        break;
    catch ME
        lastReadError = ME;
    end
end

if isempty(settings)
    error('Hardware settings read failed after %d attempt(s): %s', ...
        cfg.hardwareQueryRetries, lastReadError.message);
end

if settings(20) == 255
    error('Hardware config request returned CRC error.');
end

end

function [numChan, ptrIn, sizeIn, cfg] = build_packet_layout(settings, cfg, ChVsType, FsampVal)

numChan = zeros(10, 1);
ptrIn = zeros(11, 1);
sizeIn = zeros(11, 1);
ptrIn(1) = 1;

for inputIdx = 1:10
    probeType = double(settings(inputIdx + 1));
    if probeType >= 0 && probeType + 1 <= numel(ChVsType)
        numChan(inputIdx) = ChVsType(probeType + 1);
    end

    if ~isempty(cfg.forceInputChannelCounts) && inputIdx <= numel(cfg.forceInputChannelCounts)
        if cfg.forceInputChannelCounts(inputIdx) > 0
            numChan(inputIdx) = cfg.forceInputChannelCounts(inputIdx);
        end
    end

    if numChan(inputIdx) == 0
        cfg.IN_Active(inputIdx) = 0;
    end

    if cfg.IN_Active(inputIdx) == 1
        sizeIn(inputIdx) = (cfg.HRES(inputIdx) + 1) * ...
            FsampVal(cfg.FsampCode(inputIdx) + 1) / 500 * numChan(inputIdx);
    end

    ptrIn(inputIdx + 1) = ptrIn(inputIdx) + sizeIn(inputIdx);
end

end
