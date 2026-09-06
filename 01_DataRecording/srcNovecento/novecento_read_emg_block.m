function emg = novecento_read_emg_block(dev, inputIdxList, samplesPerBlock)
%NOVECENTO_READ_EMG_BLOCK Read and decode EMG block.
%
% output : emg (channels x samples) .
% multiple channels are stacked vertically in the same order as inputIdxList.

fsActive = dev.fsInput(inputIdxList(1));
nBaseCols = samplesPerBlock * 500 / fsActive;

if mod(nBaseCols, 1) ~= 0
    error('samplesPerBlock must map to an integer number of Novecento packet columns.');
end
nBaseCols = round(nBaseCols);

nRead = dev.PacketSize1Block * nBaseCols;
rawValues = read(dev.tcpSocket, nRead, 'int16')';

if numel(rawValues) ~= nRead
    error('Short read from Novecento. Expected %d int16 values, got %d.', nRead, numel(rawValues));
end

packet = reshape(rawValues, dev.PacketSize1Block, nBaseCols);
blocks = cell(1, numel(inputIdxList));

for idx = 1:numel(inputIdxList)
    blocks{idx} = extract_input_block(packet, dev, inputIdxList(idx), nBaseCols);
end

emg = vertcat(blocks{:});

end

function emg = extract_input_block(packet, dev, inputIdx, nBaseCols)

cfg = dev.cfg;
fsInput = dev.fsInput(inputIdx);
numChannels = dev.NumChan(inputIdx);

if cfg.IN_Active(inputIdx) ~= 1
    error('Requested input %d is not active.', inputIdx);
end

inputRows = dev.Ptr_IN(inputIdx):dev.Ptr_IN(inputIdx + 1) - 1;
linearValues = reshape(packet(inputRows, :), 1, []);
nSamples = fsInput * nBaseCols / 500;

if cfg.HRES(inputIdx) == 0
    emg = cfg.GainFactor * double(reshape(linearValues, numChannels, nSamples));
else
    % The probe sends each HRES sample as [highWord, lowWord], while
    % MATLAB typecast on this little-endian system expects
    % [lowWord, highWord]. Swap each pair before reconstructing int32.
    wordPairs = reshape(linearValues, 2, []);
    reorderedWords = reshape(flipud(wordPairs), 1, []);
    int32Values = typecast(reorderedWords, 'int32');

    % HRES uses a conversion step four times smaller than 16-bit mode.
    hresGainFactor = cfg.GainFactor / 4;
    emg = hresGainFactor * double(reshape( ...
        int32Values, numChannels, nSamples));
end

end
