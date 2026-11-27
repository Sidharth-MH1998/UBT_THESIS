classdef OnlineAppDashboard < handle
    %ONLINEAPPDASHBOARD Main plots and optional windows for every acquisition mode.
    properties
        OnQuadrantSettingsChanged = []
        OnOpenExperimentalTask = []
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
        LivePlotToggle
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
        PendingForceSamples = 0
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
        RasterSelection = []
        RasterSelector = []
        RasterViewport = []
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
        QuadrantForceAxes = []
        QuadrantForceLines = []
        QuadrantLayout = []
        QuadrantSideGrid = []
        QuadrantSettingsGrid = []
        QuadrantReferenceSummary = []
    end
    methods
        function obj = OnlineAppDashboard(parent)
            tabs = uitabgroup(parent);
            feedback = uitab(tabs,'Title','Live feedback');
            grid = uigridlayout(feedback,[3 1],'RowHeight',{36,'2x','3x'}, ...
                'BackgroundColor',[0.96 0.955 0.94]);
            buttons = uigridlayout(grid,[1 5],'ColumnWidth',{120,130,130,150,'1x'}, ...
                'Padding',[0 0 0 0],'BackgroundColor',[0.96 0.955 0.94]);
            obj.RasterButton = uibutton(buttons,'Text','Raster', ...
                'Tag','openRaster','Enable','off', ...
                'ButtonPushedFcn',@(~,~) obj.openRaster());
            obj.RateButton = uibutton(buttons,'Text','Firing rates', ...
                'Tag','openFiringRates','Enable','off', ...
                'ButtonPushedFcn',@(~,~) obj.openFiringRates());
            obj.QuadrantButton = uibutton(buttons,'Text','Quadrant', ...
                'Tag','openQuadrant','Enable','off', ...
                'ButtonPushedFcn',@(~,~) obj.openQuadrant());
            uibutton(buttons,'Text','Experimental task','Tag','openExperimentalTask', ...
                'ButtonPushedFcn',@(~,~) obj.openExperimentalTask());
            obj.LivePlotToggle = uicheckbox(buttons,'Text','Plot live feedback', ...
                'Value',true,'Tag','plotLiveFeedback','FontColor',[0.12 0.12 0.12], ...
                'Tooltip','Turn off main force and EMG drawing. Acquisition, recording and separate feedback windows continue.', ...
                'ValueChangedFcn',@(~,~) obj.toggleLivePlotting());
            forcePanel = uigridlayout(grid,[2 1],'RowHeight',{24,'1x'}, ...
                'Padding',[0 0 0 0],'RowSpacing',2,'BackgroundColor',[0.96 0.955 0.94]);
            uilabel(forcePanel,'Text','Force feedback','HorizontalAlignment','center', ...
                'FontSize',13,'FontWeight','bold','FontColor',[0.12 0.12 0.12]);
            obj.ForceAxes = obj.makeAxes(forcePanel,'','Time (s)','Force (% MVC)');
            obj.ForceAxes.Tag = 'liveForceAxes';
            emgPanel = uigridlayout(grid,[2 1],'RowHeight',{24,'1x'}, ...
                'Padding',[0 0 0 0],'RowSpacing',2,'BackgroundColor',[0.96 0.955 0.94]);
            uilabel(emgPanel,'Text','Live EMG (stacked traces)','HorizontalAlignment','center', ...
                'FontSize',13,'FontWeight','bold','FontColor',[0.12 0.12 0.12]);
            obj.EMGAxes = obj.makeAxes(emgPanel,'','Time (s)','Channel');
            obj.EMGAxes.Tag = 'liveEMGAxes';
            for ax = [obj.ForceAxes obj.EMGAxes]
                ax.FontSize = 12;
                ax.XLabel.FontSize = 13;
                ax.YLabel.FontSize = 13;
            end
            pulseTab = uitab(tabs,'Title','Pulse trains');
            pulseGrid = uigridlayout(pulseTab,[2 1], ...
                'RowHeight',{32,'1x'},'BackgroundColor',[0.96 0.955 0.94]);
            obj.PulseSelector = uidropdown(pulseGrid,'Items',{'No acquisition'}, ...
                'Enable','off','ValueChangedFcn',@(~,~) obj.drawPulse());
            obj.PulseAxes = obj.makeAxes(pulseGrid,'MU pulse train','Time (s)','Amplitude');
        end

        function initialize(obj,cfg,labels)
            obj.Ready = false;
            obj.closeAdditionalWindows();
            obj.Config = cfg;
            obj.Labels = labels;
            obj.RasterSelection = 1:numel(labels);
            obj.SpikeTimes = repmat({[]},1,numel(labels));
            obj.ForceTimes = zeros(0,1);
            obj.ForceData = zeros(0,3);
            obj.PulseTimes = [];
            obj.Pulses = zeros(numel(labels),0);
            obj.LastRefresh = -inf;
            obj.PendingForceSamples = 0;
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
            legend(obj.ForceAxes,'show','TextColor',[0.12 0.12 0.12],'Color',[0.96 0.955 0.94]);
            ylim(obj.ForceAxes,[-10 80]);
            yticks(obj.ForceAxes,[-10 0:20:80]);
            obj.ForceTargetLine = yline(obj.ForceAxes,cfg.forceTargetMVC,'--', ...
                sprintf('Target: %g%% MVC',cfg.forceTargetMVC), ...
                'Color',[0.65 0.4 0],'LineWidth',2, ...
                'LabelHorizontalAlignment','right','LabelVerticalAlignment','bottom', ...
                'HandleVisibility','off','Tag','forceMVCTarget');
            if ~cfg.showForceTarget, obj.ForceTargetLine.Visible = 'off'; end
            obj.PulseSelector.ItemsData = [];
            obj.PulseSelector.Items = labels;
            obj.PulseSelector.ItemsData = 1:numel(labels);
            obj.PulseSelector.Value = 1;
            obj.PulseSelector.Enable = 'on';
            obj.PulseLine = plot(obj.PulseAxes,nan,nan,'Color',[0.5 0.2 0.65]);
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
                if obj.LivePlotToggle.Value
                    preview = 1:obj.EMGStride:n;
                    obj.EMGTimes = [obj.EMGTimes times(preview)];
                    obj.EMGData = [obj.EMGData double(frame.emg(obj.EMGRows,preview))];
                    keepEMG = obj.EMGTimes >= frame.time-cfg.visibleWindowSec;
                    obj.EMGTimes = obj.EMGTimes(keepEMG);
                    obj.EMGData = obj.EMGData(:,keepEMG);
                end
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
            obj.PendingForceSamples = obj.PendingForceSamples+size(frame.force.data,1);
            forceInterval = max(1,round(cfg.forceFs/cfg.forcePlotRateHz));
            forceDue = obj.PendingForceSamples >= forceInterval;
            if forceDue
                % Coalesce buffered samples into one redraw, retaining the remainder.
                obj.PendingForceSamples = mod(obj.PendingForceSamples,forceInterval);
                if obj.LivePlotToggle.Value
                    for idx = 1:3
                        set(obj.ForceLines(idx),'XData',obj.ForceTimes,'YData',obj.ForceData(:,idx));
                    end
                    xlim(obj.ForceAxes,obj.forceTimeLimits(forceNow,cfg.forceDisplayTimeSec));
                end
                obj.drawQuadrantForce();
            end
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
            if forceNow-obj.LastRefresh < 1/cfg.forcePlotRateHz
                if forceDue, drawnow limitrate nocallbacks; end
                return;
            end
            obj.LastRefresh = forceNow;
            if obj.LivePlotToggle.Value
                if ~isempty(obj.EMGTimes)
                    previewFs = cfg.fs/obj.EMGStride;
                    firstSample = round(obj.EMGTimes(1)*previewFs)+1;
                    novecento_plot_stacked(obj.EMGAxes,obj.EMGData, ...
                        cfg.emgPreviewChannels,previewFs,firstSample,cfg.visibleWindowSec);
                    yticklabels(obj.EMGAxes,obj.EMGLabels);
                    xlim(obj.EMGAxes,[max(0,forceNow-cfg.visibleWindowSec), ...
                        max(cfg.visibleWindowSec,forceNow)]);
                end
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

        function toggleLivePlotting(obj)
            % Drop only preview history; recorded EMG belongs to the session.
            obj.EMGTimes = [];
            obj.EMGData = zeros(numel(obj.EMGRows),0);
            obj.LastRefresh = -inf;
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
        function openExperimentalTask(obj)
            if ~isempty(obj.OnOpenExperimentalTask), obj.OnOpenExperimentalTask(); end
        end

        function openRaster(obj)
            if ~obj.Ready, return; end
            if isgraphics(obj.RasterFigure)
                figure(obj.RasterFigure); return;
            end
            obj.RasterReady = false;
            obj.RasterFigure = uifigure('Name','MU raster', ...
                'Tag','OnlineAppRasterWindow','Color',[0.96 0.955 0.94], ...
                'Position',[180 120 1100 680],'Visible','off','AutoResizeChildren','off', ...
                'CloseRequestFcn',@(~,~) obj.closePopup('raster'));
            layout = uigridlayout(obj.RasterFigure,[1 2], ...
                'ColumnWidth',{190,'1x'}, ...
                'BackgroundColor',[0.96 0.955 0.94]);
            controls = uigridlayout(layout,[4 1], ...
                'RowHeight',{24,36,32,'1x'},'Padding',[0 0 0 0], ...
                'BackgroundColor',[0.96 0.955 0.94]);
            uilabel(controls,'Text','Select motor units','FontWeight','bold', ...
                'FontColor',[0.12 0.12 0.12]);
            uilabel(controls,'Text','Ctrl/Shift-click to select multiple MUs.', ...
                'WordWrap','on','FontColor',[0.35 0.35 0.35]);
            uibutton(controls,'Text','Select all MUs','Tag','rasterSelectAll', ...
                'ButtonPushedFcn',@(~,~) obj.selectAllRasterMUs());
            obj.RasterSelector = uilistbox(controls,'Items',obj.Labels, ...
                'ItemsData',1:numel(obj.Labels),'Multiselect','on', ...
                'Value',obj.RasterSelection,'Tag','rasterMUSelector', ...
                'ValueChangedFcn',@(~,~) obj.selectRasterMUs());
            obj.RasterViewport = uigridlayout(layout,[1 1], ...
                'Scrollable','on','Tag','rasterScrollViewport', ...
                'Padding',[0 0 0 0],'BackgroundColor',[0.96 0.955 0.94]);
            obj.RasterAxes = obj.makeAxes(obj.RasterViewport,'MU raster','Time (s)','Grid / MU');
            obj.RasterAxes.Tag = 'rasterMUAxes';
            obj.rebuildRaster();
            obj.RasterFigure.SizeChangedFcn = @(~,~) obj.resizeRaster();
            obj.RasterFigure.Visible = 'on';
        end

        function selectAllRasterMUs(obj)
            obj.RasterSelector.Value = 1:numel(obj.Labels);
            obj.selectRasterMUs();
        end

        function selectRasterMUs(obj)
            obj.RasterSelection = sort(obj.RasterSelector.Value);
            obj.rebuildRaster();
        end

        function resizeRaster(obj)
            if ~isgraphics(obj.RasterFigure) || ~isgraphics(obj.RasterViewport), return; end
            % Preserve at least 28 pixels per MU; scroll instead of compressing rows.
            obj.RasterViewport.RowHeight = ...
                {max(obj.RasterFigure.Position(4)-50,28*numel(obj.RasterSelection)+90)};
        end

        function rebuildRaster(obj)
            obj.RasterReady = false;
            cla(obj.RasterAxes);
            hold(obj.RasterAxes,'on');
            colors = lines(max(3,numel(obj.Labels)));
            selected = obj.RasterSelection;
            obj.RasterLines = gobjects(1,numel(selected));
            for row = 1:numel(selected)
                mu = selected(row);
                obj.RasterLines(row) = plot(obj.RasterAxes,nan,nan,'|', ...
                    'Color',colors(mu,:),'MarkerSize',8,'LineWidth',1);
            end
            yticks(obj.RasterAxes,1:numel(selected));
            yticklabels(obj.RasterAxes,obj.Labels(selected));
            ylim(obj.RasterAxes,[0 numel(selected)+1]);
            title(obj.RasterAxes,sprintf('MU raster (%d of %d MUs)',numel(selected),numel(obj.Labels)));
            obj.resizeRaster();
            obj.RasterReady = true;
            obj.drawRaster();
        end

        function drawRaster(obj)
            if ~obj.RasterReady || isempty(obj.RasterFigure) || ~isgraphics(obj.RasterFigure)
                return;
            end
            for row = 1:numel(obj.RasterSelection)
                mu = obj.RasterSelection(row);
                times = obj.SpikeTimes{mu};
                set(obj.RasterLines(row),'XData',times,'YData',row*ones(size(times)));
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
                'Tag','OnlineAppRateWindow','Color',[0.96 0.955 0.94], ...
                'Position',[200 150 1000 600],'Visible','off', ...
                'CloseRequestFcn',@(~,~) obj.closePopup('rates'));
            layout = uigridlayout(obj.RateFigure,[2 1],'RowHeight',{32,'1x'}, ...
                'BackgroundColor',[0.96 0.955 0.94]);
            settings = uigridlayout(layout,[1 4], ...
                'ColumnWidth',{150,150,90,'1x'},'Padding',[0 0 0 0], ...
                'BackgroundColor',[0.96 0.955 0.94]);
            uicheckbox(settings,'Text','Show MU legend','Value',obj.Config.showLegend, ...
                'FontColor',[0.12 0.12 0.12],'Tag','rateShowLegend', ...
                'ValueChangedFcn',@(source,~) obj.setRateLegend(source.Value));
            uilabel(settings,'Text','Firing-rate limit (Hz)','FontColor',[0.12 0.12 0.12]);
            uieditfield(settings,'numeric','Value',obj.Config.frYLim, ...
                'Limits',[0 Inf],'LowerLimitInclusive','off','Tag','rateYLimit', ...
                'ValueChangedFcn',@(source,~) obj.setRateLimit(source.Value));
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
                legend(obj.RateAxes,'show','TextColor',[0.12 0.12 0.12], ...
                    'Color',[0.96 0.955 0.94],'FontSize',9);
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

        function setRateLegend(obj,show)
            obj.Config.showLegend = show;
            if show
                legend(obj.RateAxes,'show','TextColor',[0.12 0.12 0.12], ...
                    'Color',[0.96 0.955 0.94],'FontSize',9);
            else
                legend(obj.RateAxes,'off');
            end
        end

        function setRateLimit(obj,limit)
            obj.Config.frYLim = limit;
            ylim(obj.RateAxes,[0 limit]);
        end

        function openQuadrant(obj)
            if ~obj.Ready || numel(obj.Labels) < 2, return; end
            if isgraphics(obj.QuadrantFigure)
                figure(obj.QuadrantFigure); return;
            end
            obj.QuadrantReady = false;
            obj.QuadrantFigure = uifigure('Name','Quadrant feedback', ...
                'Tag','OnlineAppQuadrantWindow','Color',[0.96 0.955 0.94], ...
                'Position',[180 100 1060 700],'Visible','off','AutoResizeChildren','off', ...
                'CloseRequestFcn',@(~,~) obj.closePopup('quadrant'));
            layout = uigridlayout(obj.QuadrantFigure,[1 2], ...
                'ColumnWidth',{280,'1x'},'Tag','quadrantWindowLayout', ...
                'BackgroundColor',[0.96 0.955 0.94]);
            obj.QuadrantLayout = layout;
            obj.createQuadrantControls(layout);
            plotPanel = obj.makeQuadrantPanel(layout,'Quadrant feedback','quadrantPlotPanel');
            plotGrid = uigridlayout(plotPanel,[1 1],'Padding',[8 8 8 8], ...
                'BackgroundColor',[0.96 0.955 0.94]);
            obj.QuadrantAxes = obj.makeAxes(plotGrid,'Quadrant feedback','X MU (pps)','Y MU (pps)');
            obj.QuadrantAxes.Tag = 'quadrantActivityAxes';
            obj.rebuildQuadrant();
            obj.QuadrantFigure.SizeChangedFcn = @(~,~) obj.resizeQuadrant();
            obj.resizeQuadrant();
            obj.QuadrantFigure.Visible = 'on';
        end

        function resizeQuadrant(obj)
            if ~isgraphics(obj.QuadrantFigure) || ~isgraphics(obj.QuadrantAxes), return; end
            windowSize = obj.QuadrantFigure.Position(3:4);
            layout = obj.QuadrantLayout;
            scale = min(1.25,max(0.85,0.9*min(windowSize(2)/700,windowSize(1)/1060)));
            baseWidth = 280*scale;
            % Give the raster half the spare horizontal room around the square.
            spareWidth = max(0,windowSize(1)-baseWidth-windowSize(2)-70);
            layout.ColumnWidth = {baseWidth+spareWidth/2,'1x'};
            form = obj.QuadrantSettingsGrid;
            form.ColumnWidth = {145*scale,115*scale,'1x'};
            settingsHeights = [34 34 28 28 28 28 30 40 52]*scale;
            settingsHeight = sum(settingsHeights)+80*scale+42;
            plotRoom = max(220,windowSize(2)-40-settingsHeight-30*scale);
            rasterHeight = min(200*scale,0.4*plotRoom);
            forceHeight = min(300*scale,0.6*plotRoom);
            form.RowHeight = num2cell(settingsHeights);
            form.RowSpacing = 10*scale;
            obj.QuadrantSideGrid.RowHeight = {settingsHeight,rasterHeight,forceHeight,'1x'};
            obj.QuadrantSideGrid.RowSpacing = 10*scale;
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
            obj.QuadrantForceAxes.FontSize = 10*scale;
            obj.QuadrantForceAxes.XLabel.FontSize = 11*scale;
            obj.QuadrantForceAxes.YLabel.FontSize = 11*scale;
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
            obj.drawQuadrantForce();
            obj.Quadrant = struct('enabled',false);
            obj.Quadrant = ispin_quadrant_feedback('init',numel(obj.Labels), ...
                cfg.fs,cfg.blockDurationSec,cfg,obj.QuadrantAxes);
            if ~isempty(obj.Quadrant.referenceRates)
                obj.QuadrantReferenceSummary.Text = sprintf( ...
                    'X reference: %.2f pps | max: %.2f pps\nY reference: %.2f pps | max: %.2f pps\nSettings are locked while recording.', ...
                    obj.Quadrant.referenceRates(1),obj.Quadrant.axisMaxima(1), ...
                    obj.Quadrant.referenceRates(2),obj.Quadrant.axisMaxima(2));
            end
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
            obj.QuadrantSideGrid = uigridlayout(parent,[4 1], ...
                'RowHeight',{400,200,300,'1x'},'Padding',[0 0 0 0], ...
                'BackgroundColor',[0.96 0.955 0.94]);
            settingsPanel = obj.makeQuadrantPanel(obj.QuadrantSideGrid,'Settings','quadrantSettingsPanel');
            form = uigridlayout(settingsPanel,[9 3],'ColumnWidth',{145,115,'1x'}, ...
                'RowHeight',{34,34,28,28,28,28,30,40,52}, ...
                'Padding',[8 8 8 8],'BackgroundColor',[0.96 0.955 0.94]);
            obj.QuadrantSettingsGrid = form;
            fields = {'quadrantXMU','X-axis motor unit','mu'; ...
                'quadrantYMU','Y-axis motor unit','mu'; ...
                'quadrantRateWindowSec','Rate window (s)','number'; ...
                'quadrantSmoothingWindows','Smoothing windows','number'; ...
                'quadrantHistorySec','Cursor history (s)','number'; ...
                'quadrantAxisScale','Reference scale','number'; ...
                'quadrantShowReferenceLines','Show reference lines','check'};
            for idx = 1:size(fields,1)
                name = fields{idx,1};
                label = uilabel(form,'Text',fields{idx,2},'WordWrap','on', ...
                    'FontColor',[0.12 0.12 0.12]);
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
                if strcmp(name,'quadrantAxisScale')
                    control.Tooltip = 'I-Spin axis maximum = reference firing rate multiplied by this factor (default 1.5). Cursor values remain in pps.';
                end
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
                'WordWrap','on','VerticalAlignment','top','FontColor',[0.35 0.35 0.35]);
            note.Layout.Row = 9;
            note.Layout.Column = [1 2];
            obj.QuadrantReferenceSummary = note;
            rasterPanel = obj.makeQuadrantPanel(obj.QuadrantSideGrid, ...
                'Firing of selected Motor unit','quadrantRasterPanel');
            rasterGrid = uigridlayout(rasterPanel,[1 1],'Padding',[8 8 8 8], ...
                'BackgroundColor',[0.96 0.955 0.94]);
            obj.QuadrantRasterAxes = obj.makeAxes(rasterGrid,'','Time (s)','');
            obj.QuadrantRasterAxes.Tag = 'quadrantSelectedMURaster';
            obj.QuadrantRasterAxes.FontSize = 9;
            forcePanel = obj.makeQuadrantPanel(obj.QuadrantSideGrid,'Force feedback','quadrantForcePanel');
            forceGrid = uigridlayout(forcePanel,[1 1],'Padding',[8 8 8 8], ...
                'BackgroundColor',[0.96 0.955 0.94]);
            obj.QuadrantForceAxes = obj.makeAxes(forceGrid,'','Time (s)','Force (% MVC)');
            obj.QuadrantForceAxes.Tag = 'quadrantForceAxes';
            hold(obj.QuadrantForceAxes,'on');
            obj.QuadrantForceLines = gobjects(1,3);
            for idx = 1:3
                obj.QuadrantForceLines(idx) = plot(obj.QuadrantForceAxes,nan,nan, ...
                    'Color',obj.ForceLines(idx).Color, ...
                    'DisplayName',obj.ForceLines(idx).DisplayName,'Tag','quadrantForceTrace');
            end
            legend(obj.QuadrantForceAxes,'show','Location','northoutside', ...
                'Orientation','horizontal','FontSize',8, ...
                'TextColor',[0.12 0.12 0.12],'Color',[0.96 0.955 0.94]);
            ylim(obj.QuadrantForceAxes,[-10 80]);
            yticks(obj.QuadrantForceAxes,[-10 0:20:80]);
            copyobj(obj.ForceTargetLine,obj.QuadrantForceAxes);
            obj.setRecordingLocked(obj.RecordingLocked);
        end

        function drawQuadrantForce(obj)
            if ~obj.QuadrantRasterReady || ~isgraphics(obj.QuadrantForceAxes), return; end
            for idx = 1:3
                set(obj.QuadrantForceLines(idx),'XData',obj.ForceTimes, ...
                    'YData',obj.ForceData(:,idx));
            end
            forceNow = obj.CurrentTime;
            if ~isempty(obj.ForceTimes), forceNow = max(forceNow,obj.ForceTimes(end)); end
            xlim(obj.QuadrantForceAxes, ...
                obj.forceTimeLimits(forceNow,obj.Config.forceDisplayTimeSec));
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
                validateattributes(settings.quadrantAxisScale,{'numeric'}, ...
                    {'scalar','finite','positive'});
                if isfield(obj.Config,'quadrantReferenceRates') && ~isempty(obj.Config.quadrantReferenceRates)
                    references = obj.Config.quadrantReferenceRates([settings.quadrantXMU settings.quadrantYMU]);
                    assert(all(isfinite(references) & references > 0), ...
                        'Selected MUs need positive reference firing rates. Check edition.mean_fr or edited discharge times.');
                end
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
        function limits = forceTimeLimits(now,window)
            % Begin scrolling at the midpoint, retaining half a window ahead.
            startTime = max(0,now-window/2);
            limits = [startTime startTime+window];
        end

        function panel = makeQuadrantPanel(parent,titleText,tag)
            panel = uipanel(parent,'Title',titleText,'Tag',tag, ...
                'BorderType','line','HighlightColor',[0.7 0.7 0.7], ...
                'BackgroundColor',[0.96 0.955 0.94], ...
                'ForegroundColor',[0.12 0.12 0.12],'FontWeight','bold','FontSize',12);
        end

        function ax = makeAxes(parent,titleText,xText,yText)
            ax = uiaxes(parent,'Color',[0.98 0.975 0.96], ...
                'XColor',[0.15 0.15 0.15],'YColor',[0.15 0.15 0.15], ...
                'GridColor',[0.65 0.65 0.65]);
            grid(ax,'on');
            title(ax,titleText,'Color',[0.12 0.12 0.12]);
            xlabel(ax,xText); ylabel(ax,yText);
        end
    end
end
