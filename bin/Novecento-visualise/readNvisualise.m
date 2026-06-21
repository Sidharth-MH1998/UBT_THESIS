% Routine for direct communication with Novecento+ 
% Optimized for: Infinite recording, 3-channel real-time plotting, and safe exit.
% OT Bioelettronica | Updated: 2024

close all; clear all; clc;

%% --- Configuration Parameters ---
NumCycles = Inf;       % Run forever until Ctrl+C
PlotTime = 1;         % 1 second window per update
WiFi = 0;             % 0 = Ethernet/USB, 1 = WiFi
offset = 1000;        % Vertical spacing between the 3 channels (mV)

% Storage for all data
recordedEMG_Cell = {}; 
cycleCount = 1;

% Input configuration (Input 1 active, others off)
IN_Active = [1; zeros(9,1)]; 
Mode = zeros(10,1); Gain = ones(10,1); HRES = ones(10,1); 
HPF = ones(10,1); Fsamp = ones(10,1); 

FsampVal = [500 2000 4000 8000];
SizeAux = [16 64 128 256];
FSelAux = 2; 
ChVsType = [0 14 22 38 46 70 102 0 0 0 0 0 0 0 0 0];
TCPPort = 23456;
GainFactor = 0.2861; 

%% --- Building Config String ---
ConfString = uint8(zeros(1,15));
AuxFsamp = [0 16 32 48];
ConfString(1) = bin2dec('10000000') + AuxFsamp(FSelAux) + IN_Active(10)*2 + IN_Active(9);
for i = 1 : 8
    ConfString(2) = ConfString(2) + IN_Active(i)*(2^(i-1));
end
for i = 1 : 10
    ConfString(4+i) = Mode(i)*64 + Gain(i)*16 + HPF(i)*8 + HRES(i)*4 + Fsamp(i);
end
ConfString(15) = CRC8(ConfString, 14);

%% --- TCP Connection & Initialization ---
try
    if(WiFi == 1), ip = '192.168.1.1'; else, ip = '169.254.1.10'; end
    tcpScoket = tcpclient(ip, TCPPort, 'ByteOrder', 'little-endian', 'Timeout', 10);
    disp('Connected to Novecento+');

    % Get Hardware Config to calculate packet sizes
    GetSetCmd = uint8([1, 0]); GetSetCmd(2) = CRC8(GetSetCmd, 1);
    write(tcpScoket, GetSetCmd);
    Settings = read(tcpScoket, 20, 'uint8')';

    % Start Device
    write(tcpScoket, ConfString, 'uint8');

    % Calculate Packet structure
    NumActInputs = 0; Ptr_IN = zeros(11,1); Size_IN = zeros(11,1); Ptr_IN(1) = 1;
    for i = 1 : 10
        NumChan(i) = ChVsType(Settings(i+1)+1);
        if IN_Active(i) == 1
            Size_IN(i) = (HRES(i)+1)*FsampVal(Fsamp(i)+1)/500*NumChan(i);
            NumActInputs = NumActInputs + 1;
        end
        Ptr_IN(i+1) = Ptr_IN(i) + Size_IN(i);
    end
    PacketSize1Block = Ptr_IN(11)-1 + SizeAux(FSelAux) + 128;
    
    disp('Recording started. Press Ctrl+C to stop safely.');
    fig = figure('Name', 'Novecento+ Live (3 Channels)', 'Color', 'w');

    %% --- Main Acquisition Loop ---
    while cycleCount <= NumCycles && ishandle(fig)
        % Handshake commands for specific cycles
        if(cycleCount==2)
            cmd = uint8([7, 0]); cmd(2) = CRC8(cmd, 1); write(tcpScoket, cmd);
        elseif(cycleCount==7)
            cmd = uint8([6, 0]); cmd(2) = CRC8(cmd, 1); write(tcpScoket, cmd);
        end

        % Read Data Block
        Temp = read(tcpScoket, PacketSize1Block*500*PlotTime, 'int16')';
        if isempty(Temp), continue; end
        Data = reshape(Temp, PacketSize1Block, []);

        % Process Inputs
        PlotID = 1;
        for In = 1 : 10
            if IN_Active(In) == 1
                if(HRES(In) == 0)
                    T1 = reshape(Data(Ptr_IN(In):Ptr_IN(In+1)-1, :), 1, []);
                    Sig_IN = GainFactor * (int32(reshape(T1, NumChan(In), [])));
                else
                    T1 = reshape(Data(Ptr_IN(In):Ptr_IN(In+1)-1, :), 1, []);
                    T2 = typecast(int16(T1), 'int32');
                    Sig_IN = GainFactor * (reshape(T2, NumChan(In), []));
                end
                
                % SAVE DATA: Store 64 channels in cell array
                recordedEMG_Cell{cycleCount} = Sig_IN(1:min(64, NumChan(In)), :);

                % PLOT: Show only the first 3 channels
                subplot(NumActInputs, 1, PlotID);
                hold off;
                numToShow = min(3, size(Sig_IN, 1));
                for Ch = 1 : numToShow
                    plot(Sig_IN(Ch, :) + offset * (Ch-1));
                    hold on;
                end
                title(['Input ' num2str(In) ' | First ' num2str(numToShow) ' Channels']);
                ylabel('Amplitude (mV)'); xlabel('Samples');
                xlim([0 size(Sig_IN, 2)]);
                grid on;
                PlotID = PlotID + 1;
            end
        end
        drawnow limitrate;
        cycleCount = cycleCount + 1;
    end

catch ME
    fprintf('\nAcquisition stopped or interrupted: %s\n', ME.message);
end

%% --- Safe Cleanup ---
disp('Sending STOP command to device...');
ConfString(1) = 0; 
ConfString(15) = CRC8(ConfString, 14);
if exist('tcpScoket', 'var')
    write(tcpScoket, ConfString, 'uint8');
    pause(0.5);
    clear tcpScoket;
end

% Flatten cell array into one large matrix for analysis
if ~isempty(recordedEMG_Cell)
    recordedEMG = cell2mat(recordedEMG_Cell);
    disp(['Recording finished. Data saved in "recordedEMG". Total samples: ' num22str(size(recordedEMG, 2))]);
end