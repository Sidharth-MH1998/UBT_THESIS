clc
clear;
close all;
%% Automatic editing settings
autoEdit = true; % Set false to save decomposition without automatic editing.
autoEditShowPlots = true;
autoEditOverwriteOutput = false; % Set true to replace an existing edited file.
autoEditFilterMUs = true; % Remove if SIL is too low OR CoV is too high.
autoEditSILThreshold = 0.90;
autoEditCoVThreshold = 0.50; % Ratio: 0.50 means 50%.
launcherFolder = fileparts(mfilename('fullpath'));


%% Select and load the recording
[loadedFileName,loadedFilePath] = uigetfile('*.mat','Select the EMG file to decompose');

if isequal(loadedFileName,0)
    error('No .mat file was selected.');
end

loadedFile = fullfile(loadedFilePath,loadedFileName);
DataFile = load(loadedFile);
EMG = DataFile.signal; % Pass grid metadata together with the EMG data.

%% Parameters
fs = DataFile.signal.fsamp;
fs_force = 50; % Force sampling frequency (Hz), passed with the recording.
EMG.fs_force = fs_force;
badchan = inspectBadChannels(EMG.data, fs);
[EMG, selectedSegment] = selectDecompositionSegment(EMG, fs);
padLen = 200;
initialization = 0;
NITER = 50;
nbextchan =1024;        
silthr = 0.9;
covfilter = 1;
covthr = 0.5;
differentialmode = 0;
peeloff_flag = 1;
peeloffwin = 0.025;
duplicatesthresh = 0.3;
CoVDR = 0.3;
contrastfunc = 'skew';
refineMU = 1;
preproc_flag = 1;


%% Calibration (run offline decomposition once to obtain the filters)

[signal,parameters] = decompose5(EMG, fs, badchan, padLen, initialization, NITER, nbextchan, silthr, covfilter, covthr, ...
    differentialmode, peeloff_flag, peeloffwin, duplicatesthresh, CoVDR, contrastfunc, refineMU, preproc_flag, EMG.recordedForce);
parameters.selectedSegment = selectedSegment;

%% Save beside the loaded recording
[~,loadedBaseName] = fileparts(loadedFileName);
outputFile = fullfile(loadedFilePath, [loadedBaseName '-decomposed5.mat']);

if all(cellfun(@isempty,signal.Pulsetrain))
    warning('No motor units were found.');
end

save(outputFile,'signal','parameters','-v7.3');
fprintf('Saved decomposition to:\n%s\n',outputFile);

%% Automatically edit the saved decomposition
if autoEdit
    edition = edit_single_session(outputFile, Grids=1:signal.ngrid, ...
        ShowPlots=autoEditShowPlots, ...
        OverwriteOutput=autoEditOverwriteOutput, ...
        FilterMUs=autoEditFilterMUs, ...
        SILThreshold=autoEditSILThreshold, ...
        CoVThreshold=autoEditCoVThreshold);
end

function badchan = inspectBadChannels(data, fs)
% Inspect raw channels; selections use original recording channel numbers.
validateattributes(data, {'numeric'}, {'2d','nonempty','real'});
validateattributes(fs, {'numeric'}, {'scalar','positive','finite'});
nChannels = size(data,1);
nSamples = size(data,2);
selected = false(1,nChannels);
channelColors = lines(nChannels);
page = 1;
pageSize = 16;
gain = 1;
accepted = false;
fig = figure('Name','Inspect EMG channels before decomposition', ...
    'NumberTitle','off','Position',[100 80 1150 780], ...
    'CloseRequestFcn',@cancelInspection);
ax = axes('Parent',fig,'Position',[0.08 0.23 0.89 0.69]);
uicontrol(fig,'Style','text','Units','normalized', ...
    'Position',[0.04 0.94 0.92 0.04], ...
    'String','Full recording: click a channel trace to toggle bad/good (black = bad), then continue.');
uicontrol(fig,'Style','pushbutton','Units','normalized', ...
    'Position',[0.04 0.14 0.14 0.05],'String','Previous channels', ...
    'Callback',@(~,~)changePage(-1));
uicontrol(fig,'Style','pushbutton','Units','normalized', ...
    'Position',[0.19 0.14 0.14 0.05],'String','Next channels', ...
    'Callback',@(~,~)changePage(1));
uicontrol(fig,'Style','pushbutton','Units','normalized', ...
    'Position',[0.62 0.14 0.10 0.05],'String','Gain x2', ...
    'Callback',@(~,~)changeGain(2));
uicontrol(fig,'Style','pushbutton','Units','normalized', ...
    'Position',[0.73 0.14 0.10 0.05],'String','Gain /2', ...
    'Callback',@(~,~)changeGain(0.5));
status = uicontrol(fig,'Style','text','Units','normalized', ...
    'Position',[0.04 0.06 0.66 0.06],'HorizontalAlignment','left');
uicontrol(fig,'Style','pushbutton','Units','normalized', ...
    'Position',[0.68 0.04 0.28 0.08],'String','Continue to segment selection', ...
    'FontSize',13,'FontWeight','bold', ...
    'BackgroundColor',[0.20 0.65 0.30],'ForegroundColor',[1 1 1], ...
    'Callback',@finishInspection);
drawChannels();
uiwait(fig);
if isgraphics(fig)
    delete(fig);
end


if ~accepted
    error('Launchdecomp5:InspectionCancelled', ...
        'Channel inspection cancelled. Decomposition was not started.');
end
badchan = find(selected);
fprintf('Visually selected bad channels: %s\n',mat2str(badchan));

    function drawChannels()
        channels = (page-1)*pageSize+1:min(page*pageSize,nChannels);
        samples = 1:nSamples;
        traces = double(data(channels,samples));
        traces(~isfinite(traces)) = NaN;
        traces = traces-mean(traces,2,'omitnan');
        % One common scale preserves amplitude differences between channels.
        scale = median(sqrt(mean(traces.^2,2,'omitnan')),'omitnan');
        if ~isfinite(scale) || scale <= 0
            scale = 1;
        end
        cla(ax);
        hold(ax,'on');
        for row = 1:numel(channels)
            channel = channels(row);
            color = channelColors(channel,:);
            if selected(channel)
                color = [0 0 0];
            end
            plot(ax,(samples-1)/fs, ...
                row + gain*traces(row,:)/(6*scale), ...
                'Color',color,'ButtonDownFcn',@(~,~)toggleChannel(channel));
        end
        hold(ax,'off');
        set(ax,'YDir','reverse','YTick',1:numel(channels), ...
            'YTickLabel',string(channels),'YLim',[0 numel(channels)+1]);
        xlim(ax,[(samples(1)-1)/fs max(samples(end)/fs,samples(1)/fs)]);
        xlabel(ax,'Time (s)');
        ylabel(ax,'Original channel number');
        title(ax,sprintf('Channels %d-%d of %d | Gain %.3g', ...
            channels(1),channels(end),nChannels,gain));
        set(status,'String',sprintf('Bad channels: %s',mat2str(find(selected))));
    end

    function toggleChannel(channel)
        selected(channel) = ~selected(channel);
        drawChannels();
    end

    function changePage(step)
        page = min(max(1,page+step),ceil(nChannels/pageSize));
        drawChannels();
    end

    function changeGain(factor)
        gain = gain*factor;
        drawChannels();
    end

    function finishInspection(~,~)
        accepted = true;
        uiresume(fig);
    end

    function cancelInspection(~,~)
        uiresume(fig);
    end
end

function [recording, segment] = selectDecompositionSegment(recording, fs)
% Select on signal.path; trim raw force using its own sampling frequency.
nSamples = size(recording.data,2);
assert(nSamples >= 2,'At least two EMG samples are needed to select a segment.');
duration = (nSamples-1)/fs;
hasForce = isfield(recording,'recordedForce') && ~isempty(recording.recordedForce);
if ~isfield(recording,'path') || ~isnumeric(recording.path) || ...
        ~isvector(recording.path) || numel(recording.path) ~= nSamples
    error('Launchdecomp5:InvalidPath', ...
        'signal.path must be a numeric vector with one value per EMG sample.');
end
force = recording.path(:);
forceTime = (0:nSamples-1)'/fs;
forceTitle = 'Select the interval to decompose';
range = [0 duration];
clickStart = [];
accepted = false;
fig = figure('Name','Choose signal segment from force','NumberTitle','off', ...
    'Position',[140 140 1100 650],'CloseRequestFcn',@cancelSelection);
ax = axes('Parent',fig,'Position',[0.08 0.30 0.88 0.60]);
plot(ax,forceTime,force);
grid(ax,'on');
xlim(ax,[0 duration]);
xlabel(ax,'Time in original recording (s)');
ylabel(ax,'Force (% MVC)');
title(ax,forceTitle);
hold(ax,'on');
limits = ylim(ax);
highlight = patch(ax,[range fliplr(range)], ...
    [limits(1) limits(1) limits(2) limits(2)], [0.3 0.7 0.3], ...
    'FaceAlpha',0.15,'EdgeColor','none','HitTest','off');
startLine = xline(ax,range(1),'--k','Start','HitTest','off');
endLine = xline(ax,range(2),'--k','End','HitTest','off');
uicontrol(fig,'Style','text','Units','normalized', ...
    'Position',[0.05 0.93 0.90 0.04], ...
    'String','Click twice on the force plot to choose the start and end, or enter times below.');
uicontrol(fig,'Style','text','Units','normalized', ...
    'Position',[0.06 0.19 0.10 0.04],'String','Start (s)');
startBox = uicontrol(fig,'Style','edit','Units','normalized', ...
    'Position',[0.16 0.19 0.12 0.05],'String','0','Callback',@editRange);
uicontrol(fig,'Style','text','Units','normalized', ...
    'Position',[0.30 0.19 0.10 0.04],'String','End (s)');
endBox = uicontrol(fig,'Style','edit','Units','normalized', ...
    'Position',[0.40 0.19 0.12 0.05],'String',num2str(duration,17), ...
    'Callback',@editRange);
message = uicontrol(fig,'Style','text','Units','normalized', ...
    'Position',[0.06 0.07 0.60 0.07],'HorizontalAlignment','left');
uicontrol(fig,'Style','pushbutton','Units','normalized', ...
    'Position',[0.56 0.19 0.16 0.05],'String','Use full recording', ...
    'Callback',@resetRange);
uicontrol(fig,'Style','pushbutton','Units','normalized', ...
    'Position',[0.68 0.06 0.28 0.09],'String','Decompose selected segment', ...
    'FontSize',13,'FontWeight','bold', ...
    'BackgroundColor',[0.20 0.65 0.30],'ForegroundColor',[1 1 1], ...
    'Callback',@finishSelection);
set(fig,'WindowButtonDownFcn',@plotClick);
updateRange();
uiwait(fig);
if isgraphics(fig), delete(fig); end
if ~accepted
    error('Launchdecomp5:SelectionCancelled', ...
        'Time selection cancelled. Decomposition was not started.');
end
first = max(1,ceil(range(1)*fs-1e-7)+1);
last = min(nSamples,floor(range(2)*fs+1e-7)+1);
segment = struct('originaldata',recording.data, ...
    'startplateau',first,'endplateau',last);
% Keep original channel numbering so bad-channel indices and grids stay valid.
recording.data = recording.data(:,first:last);
for field = {'path','target'}
    name = field{1};
    if isfield(recording,name) && numel(recording.(name)) == nSamples
        recording.(name) = recording.(name)(first:last);
    end
end
if ~hasForce
    recording.recordedForce = [];
elseif first ~= 1 || last ~= nSamples
    % Keep existing force samples within the selected EMG interval.
    forceFirst = max(1,ceil((first-1)/fs*recording.fs_force-1e-7)+1);
    forceLast = min(size(recording.recordedForce,1), ...
        floor((last-1)/fs*recording.fs_force+1e-7)+1);
    recording.recordedForce = recording.recordedForce(forceFirst:forceLast,:);
end
fprintf('Selected original samples %d:%d (%.6f to %.6f s).\n', ...
    first,last,(first-1)/fs,(last-1)/fs);

    function plotClick(~,~)
        if ~isequal(ancestor(hittest(fig),'axes'),ax), return; end
        point = get(ax,'CurrentPoint');
        time = min(duration,max(0,point(1,1)));
        if isempty(clickStart)
            clickStart = time;
            set(startLine,'Value',time);
            set(message,'String','Now click the other end of the segment.');
        else
            range = sort([clickStart time]);
            clickStart = [];
            updateRange();
        end
    end

    function editRange(~,~)
        range = [str2double(get(startBox,'String')) str2double(get(endBox,'String'))];
        clickStart = [];
        updateRange();
    end

    function updateRange()
        set(startBox,'String',num2str(range(1),17));
        set(endBox,'String',num2str(range(2),17));
        if any(~isfinite(range)) || range(1) < 0 || range(2) > duration || ...
                floor(range(2)*fs+1e-7) <= ceil(range(1)*fs-1e-7)
            set(message,'String','Enter a valid start < end within the recording (at least two EMG samples).');
            return;
        end
        set(startLine,'Value',range(1));
        set(endLine,'Value',range(2));
        set(highlight,'XData',[range fliplr(range)]);
        set(message,'String',sprintf('Selected %.3f to %.3f s (%.3f s).', ...
            range(1),range(2),diff(range)));
    end

    function resetRange(~,~)
        range = [0 duration];
        clickStart = [];
        updateRange();
    end

    function finishSelection(~,~)
        if ~isempty(clickStart)
            set(message,'String','Click the other end of the segment first.');
            return;
        end
        editRange();
        if any(~isfinite(range)) || range(1) < 0 || range(2) > duration || ...
                floor(range(2)*fs+1e-7) <= ceil(range(1)*fs-1e-7)
            return;
        end
        accepted = true;
        uiresume(fig);
    end

    function cancelSelection(~,~)
        uiresume(fig);
    end
end
