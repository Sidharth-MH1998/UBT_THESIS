function [tcpSocket, NumEMGChanSessn,TCPPort, OffsetEMG, PlotTime, DeviceEN, EMG, NumChan, Mode, SyncStatChan, TotNumChan, TotNumByte, ConfString, blockData] = setupSyncstationWithSessantaquattro()


TCPPort = 54320;
OffsetEMG = 1000;
PlotTime = 1/50; % to match force data stream
% ---------- Muovi 1 ------------------------------------------------------
DeviceEN(1) = 0;    % 1=Muovi enabled, 0=Muovi disabled
EMG(1) = 1;         % 1=EMG, 0=EEG
Mode(1) = 0;        % 0=32Ch Monop, 1=16Ch Monop, 2=32Ch ImpCk, 3=32Ch Test
% ---------- Muovi 2 ------------------------------------------------------
DeviceEN(2) = 0;    % 1=Muovi enabled, 0=Muovi disabled
EMG(2) = 1;         % 1=EMG, 0=EEG
Mode(2) = 3;        % 0=32Ch Monop, 1=16Ch Monop, 2=32Ch ImpCk, 3=32Ch Test
% ---------- Muovi 3 ------------------------------------------------------
DeviceEN(3) = 0;    % 1=Muovi enabled, 0=Muovi disabled
EMG3 = 1;           % 1=EMG, 0=EEG
Mode3 = 0;          % 0=32Ch Monop, 1=16Ch Monop, 2=32Ch ImpCk, 3=32Ch Test
% ---------- Muovi 4 ------------------------------------------------------
DeviceEN(4) = 0;    % 1=Muovi enabled, 0=Muovi disabled
EMG(4) = 1;         % 1=EMG, 0=EEG
Mode(4) = 3;        % 0=32Ch Monop, 1=16Ch Monop, 2=32Ch ImpCk, 3=32Ch Test
% ---------- Sessantaquattro 1 /Muovi+ 1 ----------------------------------
DeviceEN(5) = 1;    % 1=Sessantaquattro enabled, 0=Sessantaquattro disabled
EMG(5) = 1;         % 1=EMG, 0=EEG
Mode(5) = 0;        % 0=64Ch Monop, 1=32Ch Monp, 2=64Ch ImpCk, 3=64Ch Test
% ---------- Sessantaquattro 2 /Muovi+ 2-----------------------------------
DeviceEN(6) = 1;    % 1=Sessantaquattro enabled, 0=Sessantaquattro disabled
EMG(6) = 1;         % 1=EMG, 0=EEG
Mode(6) = 0;        % 0=64Ch Monop, 1=32Ch Monop, 2=64Ch ImpCk, 3=64Ch Test
% ---------- Dueplus 1 ----------------------------------------------------
DeviceEN(7) = 0;    % 1=Due+ enabled, 0=Due+ disabled
EMG(7) = 1;         % 1=EMG(just this mode is available)
Mode(7) = 0;      
% ---------- Dueplus 2 ----------------------------------------------------
DeviceEN(8) = 0;    % 1=Due+ enabled,0=Due+ disabled
EMG(8) = 1;         % 1=EMG(just this mode is available)
Mode(8) = 3;    
% ---------- Dueplus 3 ----------------------------------------------------
DeviceEN(9) = 0;    % 1=Due+ enabled, 0=Due+ disabled
EMG(9) = 1;         % 1=EMG(just this mode is available)
Mode(9) = 3;     
% ---------- Dueplus 4 ----------------------------------------------------
DeviceEN(10) = 0;   % 1=Due+ enabled, 0=Due+ disabled
EMG(10) = 1;        % 1=EMG(just this mode is available)
Mode(10) = 3;       
% ---------- Dueplus 5 ----------------------------------------------------
DeviceEN(11) = 0;   % 1=Due+ enabled, 0=Due+ disabled
EMG(11) = 1;        % 1=EMG(just this mode is available)
Mode(11) = 3;       
% ---------- Dueplus 6 ----------------------------------------------------
DeviceEN(12) = 0;   % 1=Due+ enabled, 0=Due+ disabled
EMG(12) = 1;        % 1=EMG(just this mode is available)
Mode(12) = 3;       
% ---------- Dueplus 7 ----------------------------------------------------
DeviceEN(13) = 0;   % 1=Due+ enabled, 0=Due+ disabled
EMG(13) = 1;        % 1=EMG(just this mode is available)
Mode(13) = 3;       
% ---------- Dueplus 8 ----------------------------------------------------
DeviceEN(14) = 0;   % 1=Due+ enabled, 0=Due+ disabled
EMG(14) = 1;        % 1=EMG(just this mode is available)
Mode(14) = 3;       
% ---------- Quattroplus 1 ------------------------------------------------
DeviceEN(15) = 0;   % 1=Quattro+ enabled, 0=Quattro+ disabled
EMG(15) = 1;        % 1=EMG(just this mode is available)
Mode(15) = 3;       
% ---------- Quattroplus 2 ------------------------------------------------
DeviceEN(16) = 0;   % 1=Quattro+ enabled, 0=Quattro+ disabled
EMG(16) = 1;        % 1=EMG(just this mode is available)
Mode(16) = 3;       

% Number of acquired channel depending on the acquisition mode
NumChan = [38 38 38 38 70 70 8 8 8 8 8 8 8 8 10 10];

Error = 0;
for i = 1 : 16
    if(DeviceEN(i) > 1)
        Error = 1;
    end
end

if(Error == 1)
    disp("Error, set DeviceEN values equal to 0 or 1")
    return;
end

Error = 0;
for i = 1 : 16
    if(EMG(i) > 1)
        Error = 1;
    end
end

if(Error == 1)
    disp("Error, set EMG values equal to 0 or 1")
    return;
end
      

Error = 0;
for i = 1 : 16
    if(Mode(i) > 3)
        Error = 1;
    end
end

if(Error == 1)
    disp("Error, set Mode values between to 0 and 3")
    return;
end

SizeComm = 0;
for i = 1 : 16
    SizeComm = SizeComm + DeviceEN(i);
end
     
NumEMGChanMuovi = 0;
NumAUXChanMuovi = 0;
NumEMGChanSessn = 0;
NumAUXChanSessn = 0;
NumEMGChanDuePl = 0;
NumAUXChanDuePl = 0;
NumEMGChanQuattroPl = 0;
NumAUXChanQuattroPl = 0;
muoviEMGChan = double.empty;
muoviAUXChan = double.empty;
sessnEMGChan = double.empty;
sessnAUXChan = double.empty;
duePlEMGChan = double.empty;
duePlAUXChan = double.empty;
quattroPlEMGChan = double.empty;
quattroPlAUXChan = double.empty;

sampFreq = 2000;
TotNumChan = 0;
TotNumByte = 0;
ConfStrLen = 2;
ConfString = zeros(18,1);

ConfString(1) = SizeComm*2 + 1;

for i = 1 : 16
    if DeviceEN(i) == 1
        ConfString(ConfStrLen) = (i-1)*16 + EMG(i)*8 + Mode(i)*2 + 1;
        
        if(i < 5)
            muoviEMGChan = [muoviEMGChan, TotNumChan+1:TotNumChan+32];
            muoviAUXChan = [muoviAUXChan, TotNumChan+33:TotNumChan+38];
            NumEMGChanMuovi = NumEMGChanMuovi + 32;
            NumAUXChanMuovi = NumAUXChanMuovi + 6;
        elseif(i > 6)
            duePlEMGChan = [duePlEMGChan, TotNumChan+1:TotNumChan+2];
            duePlAUXChan = [duePlAUXChan, TotNumChan+3:TotNumChan+8];
            NumEMGChanDuePl = NumEMGChanDuePl + 2;
            NumAUXChanDuePl = NumAUXChanDuePl + 6;
        else
            sessnEMGChan = [sessnEMGChan, TotNumChan+1:TotNumChan+64];
            sessnAUXChan = [sessnAUXChan, TotNumChan+65:TotNumChan+70];
            NumEMGChanSessn = NumEMGChanSessn + 64;
            NumAUXChanSessn = NumAUXChanSessn + 6;
        end
       
        TotNumChan = TotNumChan + NumChan(i);
        
        if(EMG(i) == 1)
            TotNumByte = TotNumByte + NumChan(i) * 2;
        else
            TotNumByte = TotNumByte + NumChan(i) * 3;
        end

        if EMG(i) == 1
            sampFreq = 2000;
        end
        ConfStrLen = ConfStrLen+1;
    end
end

SyncStatChan = TotNumChan+1:TotNumChan+6;
TotNumChan = TotNumChan + 6;
TotNumByte = TotNumByte + 12;

ConfString(ConfStrLen) = CRC8(ConfString, ConfStrLen-1);

% Open the TCP socket
if verLessThan('matlab','9.12')
    tcpSocket = tcpip('192.168.76.1', TCPPort, 'NetworkRole', 'client');
    tcpSocket.InputBufferSize = TotNumChan * sampFreq * 3; % 2 s of data with all ch @ 2kHz
    fopen(tcpSocket);
    set(tcpSocket, 'ByteOrder', 'littleEndian');
else
   % Open the TCP socket as client
    tcpSocket = tcpclient('192.168.76.1',TCPPort);
    tcpSocket.InputBufferSize = TotNumChan * sampFreq * 3; % 2 s of data with all ch @ 2kHz
    fopen(tcpSocket);
    set(tcpSocket, 'ByteOrder', 'little-endian');
end


% One second of data: 2 bytes * channels * Sampling frequency
% blockData = 2*TotNumChan*sampFreq*PlotTime;
blockData = TotNumByte*sampFreq*PlotTime;

% Send the configuration to muovi station
fwrite(tcpSocket, ConfString(1:ConfStrLen), 'uint8');

end