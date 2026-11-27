% Replay recorded EMG through the online decomposition decoder.
% Results are returned in data_out, as in StartOnlineDecompositionV3.
[calibrationName, calibrationFolder] = uigetfile('*.mat', ...
    'Select decomposed or edited MUedit result');
if isequal(calibrationName, 0)
    return;
end
[recordingName, recordingFolder] = uigetfile(fullfile(calibrationFolder, '*.mat'), ...
    'Select recorded EMG to replay');
if isequal(recordingName, 0)
    return;
end

% Leave empty when the recording already uses calibration electrode order.
% Otherwise list the recording row for each calibration electrode in order.
recordingRows = [];
data_out = replayOfflineEMG(fullfile(calibrationFolder, calibrationName), ...
    fullfile(recordingFolder, recordingName), recordingRows);
