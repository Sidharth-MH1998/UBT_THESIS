function otb = otb4_to_mat_and_plot(otb4File, outMatFile)
% OTB4_TO_MAT_AND_PLOT Convert an OTBioLab .otb4 file to .mat and plot EMG.
%
% Usage:
%   otb = otb4_to_mat_and_plot
%   otb = otb4_to_mat_and_plot('myfile.otb4')
%   otb = otb4_to_mat_and_plot('myfile.otb4', 'myfile_converted.mat')
%
% The output MAT file contains:
%   otb.emg              selected EMG channels x samples
%   otb.time             time vector in seconds
%   otb.fs               sampling frequency
%   otb.track            parsed EMG track metadata
%   otb.allTrackSamples  full signal stream channels x samples
%   otb.tracks           all parsed tracks from Tracks_000.xml
%   otb.deviceXml        text from DeviceParameters.xml
%   otb.tracksXml        text from Tracks_000.xml

if nargin < 1 || isempty(otb4File)
    [fileName, folderName] = uigetfile({'*.otb4;*.otb+', 'OTBioLab files (*.otb4, *.otb+)'; '*.*', 'All files'}, ...
        'Choose an OTBioLab file');
    if isequal(fileName, 0)
        error('No OTBioLab file selected.');
    end
    otb4File = fullfile(folderName, fileName);
end

if nargin < 2 || isempty(outMatFile)
    [folderName, baseName] = fileparts(otb4File);
    outMatFile = fullfile(folderName, [baseName '_converted.mat']);
end

if ~isfile(otb4File)
    error('File not found: %s', otb4File);
end

extractDir = fullfile(tempdir, ['otb4_extract_' char(javaMethod('randomUUID', 'java.util.UUID'))]);
mkdir(extractDir);
cleanupObj = onCleanup(@() cleanup_extract_dir(extractDir)); %#ok<NASGU>

untar(otb4File, extractDir);

tracksXmlFile = fullfile(extractDir, 'Tracks_000.xml');
deviceXmlFile = fullfile(extractDir, 'DeviceParameters.xml');

if ~isfile(tracksXmlFile)
    error('Tracks_000.xml was not found inside: %s', otb4File);
end

tracksXml = fileread(tracksXmlFile);
deviceXml = '';
if isfile(deviceXmlFile)
    deviceXml = fileread(deviceXmlFile);
end

tracks = parse_otb4_tracks(tracksXml);
emgTrack = choose_emg_track(tracks);

sigFile = fullfile(extractDir, emgTrack.SignalStreamPath);
if ~isfile(sigFile)
    error('Signal stream not found inside OTB4: %s', emgTrack.SignalStreamPath);
end

sampleType = sample_type_from_track(emgTrack);
fid = fopen(sigFile, 'r');
if fid < 0
    error('Could not open signal stream: %s', sigFile);
end
raw = fread(fid, Inf, sampleType);
fclose(fid);

totalChannels = emgTrack.TotalChannelsInFile;
if isempty(totalChannels) || totalChannels <= 0
    totalChannels = emgTrack.ChannelsInBlock;
end
if isempty(totalChannels) || totalChannels <= 0
    error('Could not determine TotalChannelsInFile for EMG track.');
end

nSamples = floor(numel(raw) / totalChannels);
raw = raw(1:(nSamples * totalChannels));
allTrackSamples = reshape(double(raw), totalChannels, nSamples);

firstRow = emgTrack.ChannelOffsetInSubPacket + 1;
nEmgChannels = emgTrack.MaxNumberOfChannels;
if isempty(nEmgChannels) || nEmgChannels <= 0
    nEmgChannels = emgTrack.NumberOfChannels;
end
if isempty(nEmgChannels) || nEmgChannels <= 0
    nEmgChannels = totalChannels - firstRow + 1;
end

lastRow = min(totalChannels, firstRow + nEmgChannels - 1);
emg = allTrackSamples(firstRow:lastRow, :);

fs = emgTrack.SamplingFrequency;
if isempty(fs) || fs <= 0
    error('Could not determine SamplingFrequency for EMG track.');
end
time = (0:(size(emg, 2) - 1)) / fs;

otb = struct();
otb.sourceFile = otb4File;
otb.outputMatFile = outMatFile;
otb.emg = emg;
otb.time = time;
otb.fs = fs;
otb.track = emgTrack;
otb.allTrackSamples = allTrackSamples;
otb.tracks = tracks;
otb.deviceXml = deviceXml;
otb.tracksXml = tracksXml;

save(outMatFile, 'otb', '-v7.3');

fprintf('Created MAT file:\n%s\n', outMatFile);
fprintf('EMG size: %d channels x %d samples\n', size(otb.emg, 1), size(otb.emg, 2));
fprintf('Sampling rate: %.0f Hz\n', otb.fs);
fprintf('Duration: %.3f seconds\n', otb.time(end));
fprintf('Selected track: %s | %s | %s\n', otb.track.Title, otb.track.SubTitle, otb.track.SignalStreamPath);

plot_otb4_emg(otb);

end

function tracks = parse_otb4_tracks(xmlText)
blocks = regexp(xmlText, '<TrackInfo>(.*?)</TrackInfo>', 'tokens');
tracks = repmat(empty_track(), 0, 1);

for i = 1:numel(blocks)
    block = blocks{i}{1};
    tr = empty_track();
    tr.Title = get_text_tag(block, 'Title');
    tr.SubTitle = get_text_tag(block, 'SubTitle');
    tr.Device = get_text_tag(block, 'Device');
    tr.SignalStreamPath = get_text_tag(block, 'SignalStreamPath');
    tr.UnitOfMeasurement = get_text_tag(block, 'UnitOfMeasurement');
    tr.IsControl = get_bool_tag(block, 'IsControl');
    tr.IsProcessing = get_bool_tag(block, 'IsProcessing');
    tr.MaxNumberOfChannels = get_num_tag(block, 'MaxNumberOfChannels');
    tr.NumberOfChannels = get_num_tag(block, 'NumberOfChannels');
    tr.TotalChannelsInFile = get_num_tag(block, 'TotalChannelsInFile');
    tr.ChannelsInBlock = get_num_tag(block, 'ChannelsInBlock');
    tr.ChannelOffsetInSubPacket = get_num_tag(block, 'ChannelOffsetInSubPacket');
    tr.SamplingFrequency = get_num_tag(block, 'SamplingFrequency');
    tr.SampleSize = get_num_tag(block, 'SampleSize');
    tr.ADC_Nbits = get_num_tag(block, 'ADC_Nbits');
    tr.ADC_Range = get_num_tag(block, 'ADC_Range');
    tr.UnitOfMeasurementFactor = get_num_tag(block, 'UnitOfMeasurementFactor');
    tr.TimeDuration = get_num_tag(block, 'TimeDuration');
    tr.Mode = get_nested_text_tag(block, 'StringsDescriptions', 'Mode');
    tr.Channels = get_nested_text_tag(block, 'StringsDescriptions', 'Channels');
    tr.FileType = get_nested_text_tag(block, 'StringsDescriptions', 'FileType');
    tr.LowPassFilter = get_nested_text_tag(block, 'StringsDescriptions', 'LowPassFilter');
    tr.HighPassFilter = get_nested_text_tag(block, 'StringsDescriptions', 'HighPassFilter');
    tr.StartDate = get_nested_text_tag(block, 'StringsDescriptions', 'StartDate');
    tr.EndDate = get_nested_text_tag(block, 'StringsDescriptions', 'EndDate');
    tracks(end + 1, 1) = tr; %#ok<AGROW>
end
end

function tr = empty_track()
tr = struct( ...
    'Title', '', ...
    'SubTitle', '', ...
    'Device', '', ...
    'SignalStreamPath', '', ...
    'UnitOfMeasurement', '', ...
    'IsControl', false, ...
    'IsProcessing', false, ...
    'MaxNumberOfChannels', [], ...
    'NumberOfChannels', [], ...
    'TotalChannelsInFile', [], ...
    'ChannelsInBlock', [], ...
    'ChannelOffsetInSubPacket', 0, ...
    'SamplingFrequency', [], ...
    'SampleSize', [], ...
    'ADC_Nbits', [], ...
    'ADC_Range', [], ...
    'UnitOfMeasurementFactor', [], ...
    'TimeDuration', [], ...
    'Mode', '', ...
    'Channels', '', ...
    'FileType', '', ...
    'LowPassFilter', '', ...
    'HighPassFilter', '', ...
    'StartDate', '', ...
    'EndDate', '');
end

function track = choose_emg_track(tracks)
if isempty(tracks)
    error('No tracks found in Tracks_000.xml.');
end

score = zeros(numel(tracks), 1);
for i = 1:numel(tracks)
    tr = tracks(i);
    text = lower(strjoin({tr.Title, tr.SubTitle, tr.Channels, tr.FileType, tr.UnitOfMeasurement}, ' '));
    if ~tr.IsControl
        score(i) = score(i) + 10;
    end
    if contains(text, 'raw')
        score(i) = score(i) + 5;
    end
    if contains(text, 'in1') || contains(text, '1 - 64')
        score(i) = score(i) + 5;
    end
    if contains(text, 'mv')
        score(i) = score(i) + 3;
    end
    if ~isempty(tr.MaxNumberOfChannels)
        score(i) = score(i) + tr.MaxNumberOfChannels / 100;
    end
end

[~, idx] = max(score);
track = tracks(idx);
end

function sampleType = sample_type_from_track(track)
if track.SampleSize == 4
    sampleType = 'int32=>int32';
elseif track.SampleSize == 2
    sampleType = 'int16=>int16';
else
    error('Unsupported SampleSize: %g', track.SampleSize);
end
end

function value = get_text_tag(text, tag)
tok = regexp(text, ['<' tag '>(.*?)</' tag '>'], 'tokens', 'once');
if isempty(tok)
    value = '';
else
    value = strtrim(regexprep(tok{1}, '\s+', ' '));
end
end

function value = get_nested_text_tag(text, parentTag, childTag)
parent = regexp(text, ['<' parentTag '>(.*?)</' parentTag '>'], 'tokens', 'once');
if isempty(parent)
    value = '';
else
    value = get_text_tag(parent{1}, childTag);
end
end

function value = get_num_tag(text, tag)
txt = get_text_tag(text, tag);
if isempty(txt)
    value = [];
else
    value = str2double(txt);
end
end

function value = get_bool_tag(text, tag)
txt = lower(get_text_tag(text, tag));
value = strcmp(txt, 'true');
end

function plot_otb4_emg(otb)
figure('Name', 'OTB4 EMG preview', 'Color', 'w');
ax = axes;

previewChannels = 1:min(16, size(otb.emg, 1));
plotBlock = double(otb.emg(previewChannels, :));

hold(ax, 'on');
offset = max(max(std(plotBlock, 0, 2) * 6), 1);
for i = 1:numel(previewChannels)
    plot(ax, otb.time, plotBlock(i, :) + offset * (i - 1), 'LineWidth', 1);
end
hold(ax, 'off');

grid(ax, 'on');
xlabel(ax, 'Time (s)');
ylabel(ax, 'Channel');
title(ax, sprintf('OTB4 EMG preview | %d of %d channels', numel(previewChannels), size(otb.emg, 1)));
yticks(ax, offset * (0:(numel(previewChannels) - 1)));
yticklabels(ax, cellstr(num2str(previewChannels(:))));
xlim(ax, [otb.time(1), max(otb.time(end), 1 / otb.fs)]);
ylim(ax, [-offset, offset * numel(previewChannels)]);
end

function cleanup_extract_dir(extractDir)
if isfolder(extractDir)
    try
        rmdir(extractDir, 's');
    catch
    end
end
end
