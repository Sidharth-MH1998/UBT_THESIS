function emgSample = streamEMGData(tcpSocket, numEMGChannels, blockData, TotNumByte, PlotTime, DeviceEN, EMG, NumChan, sampFreq)

ChanReady = 1;

% Wait here until one block of data has been received
while(tcpSocket.BytesAvailable < blockData)
end

Temp = fread(tcpSocket, [TotNumByte, sampFreq*PlotTime], 'uint8');

for DevId = 1 : 16
    if DeviceEN(DevId) == 1
        if(EMG(DevId) == 1)
            ChInd = (1:2:NumChan(DevId)*2);
            DataSubMatrix = Temp(ChInd,:)*256 + Temp(ChInd+1,:);

            % Search for the negative values and make the two's complement
            ind = find(DataSubMatrix >= 32768);
            DataSubMatrix(ind) = DataSubMatrix(ind) - 65536;
            
            data(ChanReady:ChanReady+NumChan(DevId)-1,:) = DataSubMatrix;
            Temp(1:NumChan(DevId)*2,:) = [];
        else
            ChInd = (1:3:NumChan(DevId)*3);
            DataSubMatrix = Temp(ChInd,:)*65536 + Temp(ChInd+1,:)*256 + Temp(ChInd+2,:);
            
                            
            % Search for the negative values and make the two's complement
            ind = find(DataSubMatrix >= 8388608);
            DataSubMatrix(ind) = DataSubMatrix(ind) - (16777216);
            
            data(ChanReady:ChanReady+NumChan(DevId)-1,:) = DataSubMatrix;
            Temp(1:NumChan(DevId)*3,:) = [];
        end
        
        clear ChInd;
        clear ind;
        clear DataSubMatrix;
        ChanReady = ChanReady + NumChan(DevId);
    end
end

ChInd = (1:2:12);
DataSubMatrix = Temp(ChInd,:)*256 + Temp(ChInd+1,:);

% Search for the negative values and make the two's complement
ind = find(DataSubMatrix >= 32768);
DataSubMatrix(ind) = DataSubMatrix(ind) - 65536;

data(ChanReady:ChanReady+5,:) = DataSubMatrix;
clear ind;
clear DataSubMatrix;

% data has shape 146 x samples, with the extra channels being auxiliary
% emgSample = data(1:numEMGChannels,:); % we normally use this per sessantaquattro/device EMG channels
emgSample = [data(1:64,:); data(71:71+63,:)] ;% we have to remove extra auxiliary channels, which are 9 apparently

end