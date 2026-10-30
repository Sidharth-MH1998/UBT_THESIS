classdef OnlineAppDashboard < handle
    %ONLINEAPPDASHBOARD Main plots and optional windows for every acquisition mode.
    properties
        OnQuadrantSettingsChanged = []
    end
    properties (Access = private)
        ForceAxes
        EMGAxes
        RasterAxes
        RateAxes
        QuadrantAxes
        PulseAxes
        PulseSelector
        ForceLines
        ForceTargetLine
        RasterLines
        RateLines
        PulseLine
        Config
        Labels
        SpikeTimes
        ForceTimes = zeros(0,1)
        ForceData = zeros(0,3)
        PulseTimes = []
        Pulses = []
        Quadrant = struct('enabled',false)
        LastRefresh = -inf
        Ready = false
        RateFigure = []
        QuadrantFigure = []
        RateButton
        QuadrantButton
        CurrentTime = 0
        QuadrantFrames = {}
        QuadrantTimes = []
        RateReady = false
        QuadrantReady = false
        RasterFigure = []
        RasterButton
        RasterReady = false
        EMGTimes = []
        EMGData = []
        EMGRows
        EMGLabels
        EMGStride
        QuadrantControls = struct()
        QuadrantApplyButton = []
        RecordingLocked = false
        QuadrantRasterAxes = []
        QuadrantRasterLines = []
        QuadrantRasterReady = false
    end
    methods
        function obj = OnlineAppDashboard(parent)
            tabs = uitabgroup(parent);
            feedback = uitab(tabs,'Title','Live feedback');
            grid = uigridlayout(feedback,[3 1],'RowHeight',{36,'1x','1x'}, ...
                'BackgroundColor',[0.14 0.14 0.14]);
            buttons = uigridlayout(grid,[1 4],'ColumnWidth',{140,160,180,'1x'}, ...
                'Padding',[0 0 0 0],'BackgroundColor',[0.14 0.14 0.14]);
            obj.RasterButton = uibutton(buttons,'Text','Raster', ...
                'Tag','openRaster','Enable','off', ...
                'ButtonPushedFcn',@(~,~) obj.openRaster());
            obj.QuadrantButton = uibutton(buttons,'Text','Quadrant', ...
                'Tag','openQuadrant','Enable','off', ...
                'ButtonPushedFcn',@(~,~) obj.openQuadrant());
            obj.RateButton = uibutton(buttons,'Text','Firing rates', ...
                'Tag','openFiringRates','Enable','off', ...
                'ButtonPushedFcn',@(~,~) obj.openFiringRates());
            obj.ForceAxes = obj.makeAxes(grid,'Force (% calibrated)','Time (s)','Force (%)');
            obj.EMGAxes = obj.makeAxes(grid,'Live EMG (stacked traces)','Time (s)','Channel');
            obj.EMGAxes.Tag = 'liveEMGAxes';
            pulseTab = uitab(tabs,'Title','Pulse trains');
            pulseGrid = uigridlayout(pulseTab,[2 1], ...
                'RowHeight',{32,'1x'},'BackgroundColor',[0.14 0.14 0.14]);
            obj.PulseSelector = uidropdown(pulseGrid,'Items',{'No acquisition'}, ...
                'Enable','off','ValueChangedFcn',@(~,~) obj.drawPulse());
            obj.PulseAxes = obj.makeAxes(pulseGrid,'MU pulse train','Time (s)','Amplitude');
        end

        function initialize(obj,cfg,labels)
            obj.Ready = false;
            obj.closeAdditionalWindows();
            obj.Config = cfg;
            obj.Labels = labels;
            obj.SpikeTimes = repmat({[]},1,numel(labels));
            obj.ForceTimes = zeros(0,1);
            obj.ForceData = zeros(0,3);
            obj.PulseTimes = [];
            obj.Pulses = zeros(numel(labels),0);
            obj.LastRefresh = -inf;
            obj.CurrentTime = 0;
            obj.QuadrantFrames = {};
            obj.QuadrantTimes = [];
            obj.EMGTimes = [];
            obj.EMGData = zeros(numel(cfg.emgPreviewChannels),0);
            [present,obj.EMGRows] = ismember(cfg.emgPreviewChannels,cfg.calibChannels);
            assert(all(present),'An EMG preview channel is missing from calibration channels.');
            obj.EMGLabels = arrayfun(@(row) sprintf('G%d Ch%d', ...
                floor((row-1)/64)+1,mod(row-1,64)+1), ...
                cfg.emgPreviewChannels,'UniformOutput',false);
            obj.EMGStride = max(1,ceil(cfg.fs/500));
            % cla preserves objects with hidden handles; remove the prior target.
            if ~isempty(obj.ForceTargetLine) && isgraphics(obj.ForceTargetLine)
                delete(obj.ForceTargetLine);
            end
            axesList = [obj.ForceAxes obj.EMGAxes obj.PulseAxes];
            for ax = axesList, cla(ax); hold(ax,'on'); end
            colors = lines(max(3,numel(labels)));
            obj.ForceLines = gobjects(1,3);
            digits = {'Thumb','Index finger','Middle finger'};
            for idx = 1:3
                obj.ForceLines(idx) = plot(obj.ForceAxes,nan,nan, ...
                    'Color',colors(idx,:),'DisplayName',digits{idx});
            end
            legend(obj.ForceAxes,'show','TextColor',[0.9 0.9 0.9],'Color',[0.15 0.15 0.15]);
            ylim(obj.ForceAxes,[-10 110]);
            yticks(obj.ForceAxes,[-10 0:20:100 110]);
            obj.ForceTargetLine = yline(obj.ForceAxes,cfg.forceTargetMVC,'--', ...
                sprintf('Target: %g%% MVC',cfg.forceTargetMVC), ...
                'Color',[1 0.85 0.2],'LineWidth',2, ...
                'LabelHorizontalAlignment','right','LabelVerticalAlignment','bottom', ...
                'HandleVisibility','off','Tag','forceMVCTarget');
            if ~cfg.showForceTarget, obj.ForceTargetLine.Visible = 'off'; end
            obj.PulseSelector.ItemsData = [];
            obj.PulseSelector.Items = labels;
            obj.PulseSelector.ItemsData = 1:numel(labels);
            obj.PulseSelector.Value = 1;
            obj.PulseSelector.Enable = 'on';
            obj.PulseLine = plot(obj.PulseAxes,nan,nan,'Color',[0.8 0.5 1]);
            obj.RateButton.Enable = 'on';
            obj.RasterButton.Enable = 'on';
            obj.QuadrantButton.Enable = 'off';
            if numel(labels) >= 2, obj.QuadrantButton.Enable = 'on'; end
            obj.Ready = true;
        end

        function update(obj,frame)
            if ~obj.Ready, return; end
            cfg = obj.Config;
            obj.CurrentTime = frame.time;
            hasEMG = ~isempty(frame.pulse);
            if hasEMG
                n = size(frame.pulse,2);
                times = ((frame.sampleCursor-n):(frame.sampleCursor-1))/cfg.fs;
                preview = 1:obj.EMGStride:n;
                obj.EMGTimes = [obj.EMGTimes times(preview)];
                obj.EMGData = [obj.EMGData double(frame.emg(obj.EMGRows,preview))];
                keepEMG = obj.EMGTimes >= frame.time-cfg.visibleWindowSec;
                obj.EMGTimes = obj.EMGTimes(keepEMG);
                obj.EMGData = obj.EMGData(:,keepEMG);
                obj.PulseTimes = [obj.PulseTimes times];
                obj.Pulses = [obj.Pulses frame.pulse];
                keep = obj.PulseTimes >= frame.time-cfg.visibleWindowSec;
                obj.PulseTimes = obj.PulseTimes(keep);
                obj.Pulses = obj.Pulses(:,keep);
                for mu = 1:numel(obj.Labels)
                    new = times(frame.spikes(:,mu));
                    previous = obj.SpikeTimes{mu};
                    previous = [previous new]; %#ok<AGROW>
                    keep = previous >= frame.time-cfg.visibleWindowSec;
                    first = find(keep,1);
                    if isempty(first)
                        previous = previous(max(1,end):end);
                    else
                        previous = previous(max(1,first-1):end);
                    end
                    obj.SpikeTimes{mu} = previous;
                end
            end
            obj.ForceTimes = [obj.ForceTimes; frame.force.sessionTime];
            obj.ForceData = [obj.ForceData; frame.force.data];
            forceNow = frame.time;
            if ~isempty(obj.ForceTimes), forceNow = max(forceNow,obj.ForceTimes(end)); end
            keep = obj.ForceTimes >= forceNow-cfg.forceDisplayTimeSec;
            obj.ForceTimes = obj.ForceTimes(keep);
            obj.ForceData = obj.ForceData(keep,:);
            if hasEMG
                % Cache only recent windows so a plot opened later shows history.
                limit = ceil((cfg.quadrantHistorySec+cfg.quadrantRateWindowSec)/ ...
                    cfg.blockDurationSec)+cfg.quadrantSmoothingWindows+2;
                obj.QuadrantFrames{end+1} = frame.spikes;
                obj.QuadrantTimes(end+1) = frame.time;
                first = max(1,numel(obj.QuadrantFrames)-limit+1);
                obj.QuadrantFrames = obj.QuadrantFrames(first:end);
                obj.QuadrantTimes = obj.QuadrantTimes(first:end);
                if obj.QuadrantReady && isgraphics(obj.QuadrantFigure)
                    obj.updateQuadrant(frame.spikes,frame.time);
                end
            end
            if forceNow-obj.LastRefresh < 1/cfg.forcePlotRateHz, return; end
            obj.LastRefresh = forceNow;
            for idx = 1:3
                set(obj.ForceLines(idx),'XData',obj.ForceTimes,'YData',obj.ForceData(:,idx));
            end
            xlim(obj.ForceAxes,[max(0,forceNow-cfg.forceDisplayTimeSec), ...
                max(cfg.forceDisplayTimeSec,forceNow)+cfg.forceBufferTimeSec]);
            if ~isempty(obj.EMGTimes)
                previewFs = cfg.fs/obj.EMGStride;
                firstSample = round(obj.EMGTimes(1)*previewFs)+1;
                novecento_plot_stacked(obj.EMGAxes,obj.EMGData, ...
                    cfg.emgPreviewChannels,previewFs,firstSample,cfg.visibleWindowSec);
                yticklabels(obj.EMGAxes,obj.EMGLabels);
            end
            obj.drawRaster();
            obj.drawQuadrantRaster();
            obj.drawRates();
            obj.drawPulse();
            drawnow limitrate nocallbacks;
        end

        function delete(obj)
            obj.closeAdditionalWindows();
        end

        function setRecordingLocked(obj,locked)
            obj.RecordingLocked = locked;
            names = fieldnames(obj.QuadrantControls);
            enabled = 'on';
            if locked, enabled = 'off'; end
            for idx = 1:numel(names)
                control = obj.QuadrantControls.(names{idx});
                if isgraphics(control), control.Enable = enabled; end
            end
            if ~isempty(obj.QuadrantApplyButton) && isgraphics(obj.QuadrantApplyButton)
                obj.QuadrantApplyButton.Enable = enabled;
            end
        end
    end
    methods (Access = private)
        function openRaster(obj)
            if ~obj.Ready, return; end
            if isgraphics(obj.RasterFigure)
                figure(obj.RasterFigure); return;
            end
            obj.RasterReady = false;
            obj.RasterFigure = uifigure('Name','MU raster', ...
                'Tag','OnlineAppRasterWindow','Color',[0.14 0.14 0.14], ...
                'Position',[180 120 1000 620],'Visible','off', ...
                'CloseRequestFcn',@(~,~) obj.closePopup('raster'));
            layout = uigridlayout(obj.RasterFigure,[1 1], ...
                'BackgroundColor',[0.14 0.14 0.14]);
            obj.RasterAxes = obj.makeAxes(layout,'MU raster','Time (s)','Grid / MU');
            hold(obj.RasterAxes,'on');
            colors = lines(max(3,numel(obj.Labels)));
            obj.RasterLines = gobjects(1,numel(obj.Labels));
            for mu = 1:numel(obj.Labels)
                obj.RasterLines(mu) = plot(obj.RasterAxes,nan,nan,'|', ...
                    'Color',colors(mu,:),'MarkerSize',8);
            end
            yticks(obj.RasterAxes,1:numel(obj.Labels));
            yticklabels(obj.RasterAxes,obj.Labels);
            ylim(obj.RasterAxes,[0 numel(obj.Labels)+1]);
            obj.RasterReady = true;
            obj.drawRaster();
            obj.RasterFigure.Visible = 'on';
        end

        function drawRaster(obj)
            if ~obj.RasterReady || isempty(obj.RasterFigure) || ~isgraphics(obj.RasterFigure)
                return;
            end
            for mu = 1:numel(obj.Labels)
                times = obj.SpikeTimes{mu};
                set(obj.RasterLines(mu),'XData',times,'YData',mu*ones(size(times)));
            end
            xlim(obj.RasterAxes,[max(0,obj.CurrentTime-obj.Config.visibleWindowSec), ...
                max(obj.Config.visibleWindowSec,obj.CurrentTime)]);
        end

        function openFiringRates(obj)
            if ~obj.Ready, return; end
            if isgraphics(obj.RateFigure)
                figure(obj.RateFigure); return;
            end
            obj.RateReady = false;
            obj.RateFigure = uifigure('Name','Firing rates', ...
                'Tag','OnlineAppRateWindow','Color',[0.14 0.14 0.14], ...
                'Position',[200 150 1000 600],'Visible','off', ...
                'CloseRequestFcn',@(~,~) obj.closePopup('rates'));
            layout = uigridlayout(obj.RateFigure,[1 1], ...
                'BackgroundColor',[0.14 0.14 0.14]);
            obj.RateAxes = obj.makeAxes(layout,'Instantaneous firing rates','Time (s)','Hz');
            hold(obj.RateAxes,'on');
            colors = lines(max(3,numel(obj.Labels)));
            obj.RateLines = gobjects(1,numel(obj.Labels));
            for mu = 1:numel(obj.Labels)
                obj.RateLines(mu) = plot(obj.RateAxes,nan,nan,'.-', ...
                    'Color',colors(mu,:),'DisplayName',obj.Labels{mu},'MarkerSize',5);
            end
            ylim(obj.RateAxes,[0 obj.Config.frYLim]);
            if obj.Config.showLegend
                legend(obj.RateAxes,'show','TextColor',[0.9 0.9 0.9], ...
                    'Color',[0.15 0.15 0.15],'FontSize',9);
            end
            obj.RateReady = true;
            obj.drawRates();
            obj.RateFigure.Visible = 'on';
        end

        function drawRates(obj)
            if ~obj.RateReady || isempty(obj.RateFigure) || ~isgraphics(obj.RateFigure), return; end
            for mu = 1:numel(obj.Labels)
                times = obj.SpikeTimes{mu};
                set(obj.RateLines(mu),'XData',times(2:end),'YData',1./diff(times));
            end
            xlim(obj.RateAxes,[max(0,obj.CurrentTime-obj.Config.visibleWindowSec), ...
                max(obj.Config.visibleWindowSec,obj.CurrentTime)]);
        end

        function openQuadrant(obj)
            if ~obj.Ready || numel(obj.Labels) < 2, return; end
            if isgraphics(obj.QuadrantFigure)
                figure(obj.QuadrantFigure); return;
            end
            obj.QuadrantReady = false;
            obj.QuadrantFigure = uifigure('Name','Quadrant feedback', ...
                'Tag','OnlineAppQuadrantWindow','Color',[0.14 0.14 0.14], ...
                'Position',[180 100 1060 700],'Visible','off','AutoResizeChildren','off', ...
                'CloseRequestFcn',@(~,~) obj.closePopup('quadrant'));
            layout = uigridlayout(obj.QuadrantFigure,[1 2], ...
                'ColumnWidth',{280,'1x'}, ...
                'BackgroundColor',[0.14 0.14 0.14]);
            obj.createQuadrantControls(layout);
            obj.QuadrantAxes = obj.makeAxes(layout,'Quadrant feedback','X MU (pps)','Y MU (pps)');
            obj.rebuildQuadrant();
            obj.QuadrantFigure.SizeChangedFcn = @(~,~) obj.resizeQuadrant();
            obj.resizeQuadrant();
            obj.QuadrantFigure.Visible = 'on';
        end

        function resizeQuadrant(obj)
            if ~isgraphics(obj.QuadrantFigure) || ~isgraphics(obj.QuadrantAxes), return; end
            windowSize = obj.QuadrantFigure.Position(3:4);
            layout = obj.QuadrantAxes.Parent;
            scale = min(1.25,max(0.85,0.9*min(windowSize(2)/700,windowSize(1)/1060)));
            baseWidth = 280*scale;
            % Give the raster half the spare horizontal room around the square.
            spareWidth = max(0,windowSize(1)-baseWidth-windowSize(2)-70);
            layout.ColumnWidth = {baseWidth+spareWidth/2,'1x'};
            form = obj.QuadrantRasterAxes.Parent;
            form.ColumnWidth = {145*scale,115*scale,'1x'};
            form.RowHeight = [num2cell([34 34 28 28 28 28 30 40 52 200]*scale),{'1x'}];
            form.RowSpacing = 10*scale;
            labels = findall(form,'-isa','matlab.ui.control.Label');
            for label = labels', label.FontSize = 10*scale; end
            names = fieldnames(obj.QuadrantControls);
            for idx = 1:numel(names)
                obj.QuadrantControls.(names{idx}).FontSize = 10*scale;
            end
            obj.QuadrantApplyButton.FontSize = 10*scale;
            obj.QuadrantAxes.FontSize = 12;
            obj.QuadrantAxes.XLabel.FontSize = 13;
            obj.QuadrantAxes.YLabel.FontSize = 13;
            obj.QuadrantRasterAxes.FontSize = 10*scale;
            obj.QuadrantRasterAxes.XLabel.FontSize = 11*scale;
        end

        function rebuildQuadrant(obj)
            obj.QuadrantReady = false;
            obj.QuadrantRasterReady = false;
            cfg = obj.Config;
            cla(obj.QuadrantRasterAxes);
            hold(obj.QuadrantRasterAxes,'on');
            colors = lines(max(3,numel(obj.Labels)));
            selected = [cfg.quadrantXMU cfg.quadrantYMU];
            obj.QuadrantRasterLines = gobjects(1,2);
            for row = 1:2
                obj.QuadrantRasterLines(row) = plot(obj.QuadrantRasterAxes,nan,nan,'|', ...
                    'Color',colors(selected(row),:),'MarkerSize',9,'LineWidth',1.2);
            end
            yticks(obj.QuadrantRasterAxes,[1 2]);
            yticklabels(obj.QuadrantRasterAxes, ...
                {'Motor unit 1','Motor unit 2'});
            obj.QuadrantRasterAxes.YAxis.FontWeight = 'bold';
            ylim(obj.QuadrantRasterAxes,[0.5 2.5]);
            obj.QuadrantRasterAxes.YDir = 'reverse';
            obj.QuadrantRasterReady = true;
            obj.drawQuadrantRaster();
            obj.Quadrant = struct('enabled',false);
            obj.Quadrant = ispin_quadrant_feedback('init',numel(obj.Labels), ...
                cfg.fs,cfg.blockDurationSec,cfg,obj.QuadrantAxes);
            xIdentity = regexprep(obj.Labels{cfg.quadrantXMU},'MU(\d+)','MU $1');
            yIdentity = regexprep(obj.Labels{cfg.quadrantYMU},'MU(\d+)','MU $1');
            xlabel(obj.QuadrantAxes,['Motor unit 1 activity (Pulses per second): ' xIdentity], ...
                'FontWeight','bold');
            ylabel(obj.QuadrantAxes,['Motor unit 2 activity (Pulses per second): ' yIdentity], ...
                'FontWeight','bold');
            frames = obj.QuadrantFrames;
            times = obj.QuadrantTimes;
            for idx = 1:numel(frames)
                obj.updateQuadrant(frames{idx},times(idx));
            end
            obj.QuadrantReady = true;
            obj.resizeQuadrant();
        end

        function createQuadrantControls(obj,parent)
            form = uigridlayout(parent,[11 3],'ColumnWidth',{145,115,'1x'}, ...
                'RowHeight',{34,34,28,28,28,28,30,40,52,200,'1x'}, ...
                'Padding',[4 4 4 4],'BackgroundColor',[0.14 0.14 0.14]);
            fields = {'quadrantXMU','X-axis motor unit','mu'; ...
                'quadrantYMU','Y-axis motor unit','mu'; ...
                'quadrantRateWindowSec','Rate window (s)','number'; ...
                'quadrantSmoothingWindows','Smoothing windows','number'; ...
                'quadrantHistorySec','Cursor history (s)','number'; ...
                'quadrantAxisMax','Axis max (0 = auto)','number'; ...
                'quadrantShowReferenceLines','Show reference lines','check'};
            for idx = 1:size(fields,1)
                name = fields{idx,1};
                label = uilabel(form,'Text',fields{idx,2},'WordWrap','on', ...
                    'FontColor',[0.9 0.9 0.9]);
                label.Layout.Row = idx;
                label.Layout.Column = 1;
                if isfield(obj.Config,name)
                    value = obj.Config.(name);
                else
                    value = true; % Reference lines default on for older configurations.
                end
                switch fields{idx,3}
                    case 'check'
                        control = uicheckbox(form,'Text','','Value',value);
                    case 'mu'
                        control = uidropdown(form,'Items',obj.Labels, ...
                            'ItemsData',1:numel(obj.Labels),'Value',value);
                    otherwise
                        if isempty(value), value = 0; end
                        control = uieditfield(form,'numeric','Value',value);
                end
                control.Tag = name;
                control.Layout.Row = idx;
                control.Layout.Column = 2;
                obj.QuadrantControls.(name) = control;
            end
            obj.QuadrantApplyButton = uibutton(form,'Text','Apply settings', ...
                'Tag','applyQuadrantSettings','ButtonPushedFcn',@(~,~) obj.applyQuadrant());
            obj.QuadrantApplyButton.Layout.Row = 8;
            obj.QuadrantApplyButton.Layout.Column = [1 2];
            note = uilabel(form,'Text', ...
                'Settings are locked while recording. Applying settings restarts the feedback history.', ...
                'WordWrap','on','VerticalAlignment','top','FontColor',[0.75 0.75 0.75]);
            note.Layout.Row = 9;
            note.Layout.Column = [1 2];
            obj.QuadrantRasterAxes = obj.makeAxes(form,'Firing of selected Motor unit','Time (s)','');
            obj.QuadrantRasterAxes.Tag = 'quadrantSelectedMURaster';
            obj.QuadrantRasterAxes.Layout.Row = 10;
            obj.QuadrantRasterAxes.Layout.Column = [1 3];
            obj.QuadrantRasterAxes.FontSize = 9;
            obj.setRecordingLocked(obj.RecordingLocked);
        end

        function drawQuadrantRaster(obj)
            if ~obj.QuadrantRasterReady || isempty(obj.QuadrantFigure) || ...
                    ~isgraphics(obj.QuadrantFigure)
                return;
            end
            selected = [obj.Config.quadrantXMU obj.Config.quadrantYMU];
            for row = 1:2
                times = obj.SpikeTimes{selected(row)};
                set(obj.QuadrantRasterLines(row),'XData',times, ...
                    'YData',row*ones(size(times)));
            end
            xlim(obj.QuadrantRasterAxes, ...
                [max(0,obj.CurrentTime-obj.Config.visibleWindowSec), ...
                max(obj.Config.visibleWindowSec,obj.CurrentTime)]);
        end

        function applyQuadrant(obj)
            try
                assert(~obj.RecordingLocked,'Stop recording before changing quadrant settings.');
                settings = struct();
                names = fieldnames(obj.QuadrantControls);
                for idx = 1:numel(names)
                    settings.(names{idx}) = obj.QuadrantControls.(names{idx}).Value;
                end
                for name = {'quadrantXMU','quadrantYMU'}
                    validateattributes(settings.(name{1}),{'numeric'}, ...
                        {'scalar','integer','positive','<=',numel(obj.Labels)});
                end
                assert(settings.quadrantXMU ~= settings.quadrantYMU, ...
                    'Choose different motor units for X and Y.');
                for name = {'quadrantRateWindowSec','quadrantHistorySec'}
                    validateattributes(settings.(name{1}),{'numeric'}, ...
                        {'scalar','finite','positive'});
                end
                validateattributes(settings.quadrantSmoothingWindows,{'numeric'}, ...
                    {'scalar','integer','finite','positive'});
                validateattributes(settings.quadrantAxisMax,{'numeric'}, ...
                    {'scalar','finite','nonnegative'});
                if settings.quadrantAxisMax == 0, settings.quadrantAxisMax = []; end
                if ~isempty(obj.OnQuadrantSettingsChanged)
                    obj.OnQuadrantSettingsChanged(settings);
                end
                for idx = 1:numel(names), obj.Config.(names{idx}) = settings.(names{idx}); end
                obj.QuadrantFrames = {};
                obj.QuadrantTimes = [];
                obj.rebuildQuadrant();
            catch exception
                uialert(obj.QuadrantFigure,exception.message,'Quadrant settings');
            end
        end

        function updateQuadrant(obj,spikes,time)
            limit = max([obj.Quadrant.historyCount,obj.Quadrant.rateWindowCount, ...
                obj.Quadrant.smoothingWindows])+2;
            for name = {'rates','rawRates','spikeCounts','time'}
                data = obj.Quadrant.(name{1});
                obj.Quadrant.(name{1}) = data(max(1,size(data,1)-limit+1):end,:);
            end
            obj.Quadrant = ispin_quadrant_feedback('update',obj.Quadrant,spikes,time);
        end

        function closeAdditionalWindows(obj)
            obj.closePopup('raster');
            obj.closePopup('rates');
            obj.closePopup('quadrant');
        end

        function closePopup(obj,type)
            switch type
                case 'raster'
                    obj.RasterReady = false;
                    fig = obj.RasterFigure;
                    obj.RasterFigure = [];
                case 'rates'
                    obj.RateReady = false;
                    fig = obj.RateFigure;
                    obj.RateFigure = [];
                case 'quadrant'
                    obj.QuadrantReady = false;
                    obj.QuadrantRasterReady = false;
                    fig = obj.QuadrantFigure;
                    obj.QuadrantFigure = [];
                    obj.QuadrantControls = struct();
                    obj.QuadrantApplyButton = [];
                    obj.Quadrant = struct('enabled',false);
            end
            if isgraphics(fig), delete(fig); end
        end

        function drawPulse(obj)
            if isempty(obj.PulseLine) || ~isgraphics(obj.PulseLine), return; end
            mu = obj.PulseSelector.Value;
            if ~isnumeric(mu), return; end
            set(obj.PulseLine,'XData',obj.PulseTimes,'YData',obj.Pulses(mu,:));
            title(obj.PulseAxes,[obj.Labels{mu} ' pulse train']);
        end
    end
    methods (Static, Access = private)
        function ax = makeAxes(parent,titleText,xText,yText)
            ax = uiaxes(parent,'Color',[0.12 0.12 0.12], ...
                'XColor',[0.85 0.85 0.85],'YColor',[0.85 0.85 0.85], ...
                'GridColor',[0.4 0.4 0.4]);
            grid(ax,'on');
            title(ax,titleText,'Color',[0.9 0.9 0.9]);
            xlabel(ax,xText); ylabel(ax,yText);
        end
    end
end
