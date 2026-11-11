classdef ExperimentalTaskWindow < handle
    properties (SetAccess=private)
        Figure
    end
    properties (Access=private)
        Controls = struct()
        StartButton
        StopButton
        CaptureButton
        ApplyButton
        ResetButton
        Defaults = struct()
        AppliedSettings
        Status
        Cursor
        Trail
        TargetShapes
        AngleShapes
        ReferenceLines
        Origin
        ForceLines
        RasterLines
        ForceAxes
        RasterAxes
        TaskAxes
        TrialTimeLabel
        TaskInstruction
        TrialTimeBar
        TrialTimeFill
        ForceTime = zeros(0,1)
        ForceData = zeros(0,3)
        RasterTime = {[],[]}
        RasterPair = []
        Active = false
        Available = false
        Capture = []
        References
        ReferenceSource
        Labels
        Cfg
        OnStart
        OnStop
        LastAuxRefresh = -Inf
        LastPhase = ''
        PreviewStatus
        PreviewSettings = []
        PreviewRates = []
        PreviewTimes = []
        PreviewTrail = zeros(0,2)
    end
    methods
        function obj = ExperimentalTaskWindow(cfg,labels,onStart,onStop)
            obj.Cfg = cfg;
            obj.Labels = labels;
            obj.References = cfg.quadrantReferenceRates;
            obj.OnStart = onStart;
            obj.OnStop = onStop;
            bg = [0.14 0.14 0.14];
            fg = [0.93 0.93 0.93];
            obj.Figure = uifigure('Name','Experimental task','Tag','onlineExperimentalTask', ...
                'Position',[100 80 1250 800],'Color',bg,'Visible','off', ...
                'CloseRequestFcn',@(~,~) obj.close());
            layout = uigridlayout(obj.Figure,[1 3],'ColumnWidth',{340,'1x','3x'}, ...
                'ColumnSpacing',12,'BackgroundColor',bg);
            panel = uipanel(layout,'Title','Experiment settings','BackgroundColor',bg,'ForegroundColor',fg);
            feedback = uigridlayout(layout,[3 1],'RowHeight',{'5x','2x','3x'}, ...
                'Padding',[0 0 0 0],'BackgroundColor',bg);
            left = uigridlayout(panel,[4 1],'RowHeight',{36,32,'1x',32},'BackgroundColor',bg);
            buttons = uigridlayout(left,[1 2],'Padding',[0 0 0 0],'BackgroundColor',bg);
            obj.StartButton = uibutton(buttons,'Text','Start task','Tag','startExperimentalTask', ...
                'BackgroundColor',[0.2 0.55 0.3],'FontColor',[1 1 1], ...
                'ButtonPushedFcn',@(~,~) obj.start());
            obj.StopButton = uibutton(buttons,'Text','Stop task','Enable','off', ...
                'ButtonPushedFcn',@(~,~) obj.OnStop());
            obj.CaptureButton = uibutton(left,'Text','Capture reference rates','Tag','captureTaskReferences', ...
                'ButtonPushedFcn',@(~,~) obj.startCapture());
            rows = {
                'xMU','X: MU1 (Lower threshold)',cfg.quadrantXMU,'mu';
                'yMU','Y: MU2 (Higher threshold)',cfg.quadrantYMU,'mu';
                'xRef','X reference (pps)',0,'number';
                'yRef','Y reference (pps)',0,'number';
                'captureSec','Reference capture (s)',5,'number';
                'referenceForce','Reference force (% MVC)','','text';
                'xGain','X gain',1,'number';
                'yGain','Y gain',1,'number';
                'targetRadius','Target radius [0 : 0.25]',0.10,'number';
                'angleInnerRadius','Angle inner radius',0.40,'number';
                'targetHold','Target hold (s)',0.875,'number';
                'angleHold','Angle hold (s)',0.875,'number';
                'timeout','Trial timeout (s)',20,'number';
                'restTime','Rest at origin (s)',2,'number';
                'restRadius','Origin radius',0.10,'number';
                'repetitions','Repetitions per target',10,'number';
                'rateWindow','Rate window (s)',1,'number';
                'smoothing','Smoothing windows',6,'number';
                'cursorHistory','Cursor history (s)',1,'number';
                'seed','Shuffle seed',randi(2^31-1),'number';
                'experimentNotes','Experiment notes','','text';
                'showReferenceLines','Show reference lines',false,'check';
                'randomize','Shuffle task order',true,'check'};
            form = uigridlayout(left,[size(rows,1) 2],'ColumnWidth',{'1x',125}, ...
                'RowHeight',repmat({27},1,size(rows,1)),'Scrollable','on', ...
                'Padding',[2 2 2 2],'RowSpacing',5,'BackgroundColor',bg);
            settingsButtons = uigridlayout(left,[1 2],'Padding',[0 0 0 0],'BackgroundColor',bg);
            obj.ResetButton = uibutton(settingsButtons,'Text','Reset to defaults', ...
                'ButtonPushedFcn',@(~,~) obj.resetSettings());
            obj.ApplyButton = uibutton(settingsButtons,'Text','Apply settings','Tag','applyExperimentalTaskSettings', ...
                'ButtonPushedFcn',@(~,~) obj.applySettings());
            for i = 1:size(rows,1)
                name = rows{i,1};
                uilabel(form,'Text',rows{i,2},'FontColor',fg);
                switch rows{i,4}
                    case 'mu'
                        control = uidropdown(form,'Items',labels,'ItemsData',1:numel(labels), ...
                            'Value',rows{i,3},'ValueChangedFcn',@(~,~) obj.loadReferences());
                    case 'check'
                        control = uicheckbox(form,'Text','','Value',rows{i,3});
                    case 'text'
                        control = uieditfield(form,'text','Value',rows{i,3});
                    otherwise
                        control = uieditfield(form,'numeric','Value',rows{i,3});
                end
                control.Tag = ['task_' name];
                obj.Controls.(name) = control;
                obj.Defaults.(name) = rows{i,3};
            end
            obj.Controls.xRef.ValueChangedFcn = @(~,~) obj.markManual(1);
            obj.Controls.yRef.ValueChangedFcn = @(~,~) obj.markManual(2);
            obj.Controls.xMU.Tooltip = 'Choose the earlier-recruited MU. Recruitment threshold is not determined by the grid or MU number.';
            obj.Controls.yMU.Tooltip = 'Choose the later-recruited MU. Recruitment threshold is not determined by the grid or MU number.';
            obj.Controls.referenceForce.Tooltip = 'Optional: enter the actual force used for the reference, if known.';
            obj.Controls.captureSec.Tooltip = 'Hold a steady contraction while capturing. Rates use spike count divided by the captured duration.';
            obj.Controls.seed.Tooltip = 'Use the same seed and repetitions per target to reproduce the same shuffled trial order.';
            obj.Controls.targetRadius.Tooltip = 'Enter a radius greater than 0 and less than 0.25.';
            obj.Controls.randomize.Tooltip = 'Checked: shuffle the trials. Unchecked: repeat TI, TII, TIII in order.';
            obj.Controls.rateWindow.Tooltip = sprintf('Acquisition block: %.0f ms. Rates and scoring update once per block.',1000*cfg.blockDurationSec);
            information = uipanel(feedback,'Title','Info','BorderType','line', ...
                'HighlightColor',[0.4 0.4 0.4],'BackgroundColor',bg,'ForegroundColor',fg);
            information.Layout.Row = 1;
            statusPanel = uigridlayout(information,[3 1],'RowHeight',{104,48,'1x'}, ...
                'Padding',[6 6 6 6],'RowSpacing',4,'BackgroundColor',bg);
            obj.Status = uilabel(statusPanel,'Text','Start acquisition in the main window. Then choose two MUs, check the references and start the task.', ...
                'WordWrap','on','VerticalAlignment','top','FontColor',fg,'FontSize',15, ...
                'FontWeight','bold','Tag','experimentalTaskStatus');
            obj.PreviewStatus = uilabel(statusPanel,'Text','Live preview starts with acquisition.', ...
                'WordWrap','on','VerticalAlignment','top','FontColor',fg,'Tag','experimentalPreviewStatus');
            [ax,quadrantPanel] = obj.makePlotPanel(layout,'Task Quadrant','','',bg,fg,24);
            quadrantPanel.Layout.Column = 3;
            quadrantGrid = ax.Parent;
            quadrantGrid.RowHeight = {24,'1x',106};
            timerPanel = uigridlayout(quadrantGrid,[4 1],'RowHeight',{26,32,20,20}, ...
                'RowSpacing',2,'Padding',[4 0 4 0],'BackgroundColor',bg);
            timerPanel.Layout.Row = 3;
            obj.TaskInstruction = uilabel(timerPanel,'Text','Use the live preview to practise moving the cursor.', ...
                'WordWrap','on','FontColor',fg,'FontSize',16,'FontWeight','bold');
            uilabel(timerPanel,'Text',['Increase motor unit 1 activity to move right.  ' ...
                'Increase motor unit 2 activity to move up.'], ...
                'WordWrap','on','FontColor',fg,'FontWeight','bold');
            obj.TrialTimeLabel = uilabel(timerPanel,'Text','Trial time left: —', ...
                'FontColor',fg,'FontWeight','bold');
            trackColor = [0.26 0.26 0.26];
            obj.TrialTimeBar = uigridlayout(timerPanel,[1 2],'ColumnWidth',{1,'1x'}, ...
                'Padding',[0 0 0 0],'ColumnSpacing',0,'BackgroundColor',trackColor);
            obj.TrialTimeFill = uipanel(obj.TrialTimeBar,'BorderType','none', ...
                'BackgroundColor',[0.16 0.65 0.48],'Visible','off');
            ax.FontSize = 16;
            ax.FontWeight = 'bold';
            obj.TaskAxes = ax;
            obj.loadReferences();
            axis(ax,'square');
            grid(ax,'off');
            lim = MotorUnitTargetTask.AxisMax;
            xlim(ax,[-0.12 lim]); ylim(ax,[-0.12 lim]);
            offset = lim*tand(30);
            obj.ReferenceLines = [
                plot(ax,[0 lim],[0 offset],'--','Color',[0.5 0.5 0.5],'Visible','off')
                plot(ax,[0 offset],[0 lim],'--','Color',[0.5 0.5 0.5],'Visible','off')];
            theta = linspace(0,2*pi,100);
            obj.TargetShapes = gobjects(1,3);
            obj.AngleShapes = gobjects(1,3);
            for k = 1:3
                obj.AngleShapes(k) = patch(ax,NaN,NaN,[0.17 0.42 0.73], ...
                    'FaceAlpha',0.21,'EdgeColor','none','Visible','off');
                obj.TargetShapes(k) = plot(ax,NaN,NaN,'LineWidth',2,'Color',[1 0.2 0.2], ...
                    'Visible','off','UserData',theta);
            end
            obj.Origin = plot(ax,0.1*cos(theta),0.1*sin(theta),'--', ...
                'Color',[0.25 0.65 1],'LineWidth',1.5);
            obj.Trail = plot(ax,NaN,NaN,'LineWidth',2,'Color',[0.65 0.65 0.65]);
            obj.Cursor = plot(ax,NaN,NaN,'o','MarkerSize',10, ...
                'MarkerFaceColor',[1 0.2 0.2],'MarkerEdgeColor','none','Tag','experimentalCursor');
            [obj.RasterAxes,rasterPanel] = obj.makePlotPanel(feedback, ...
                'Firing of selected motor units','Time (s)','',bg,fg,36);
            rasterPanel.Layout.Row = 2;
            xlim(obj.RasterAxes,[0 5]);
            xticks(obj.RasterAxes,0:5);
            ylim(obj.RasterAxes,[0.5 2.5]); yticks(obj.RasterAxes,[1 2]);
            yticklabels(obj.RasterAxes,{'X MU','Y MU'});
            obj.RasterLines = gobjects(1,2);
            for k = 1:2, obj.RasterLines(k) = plot(obj.RasterAxes,NaN,NaN,'|'); end
            [obj.ForceAxes,forcePanel] = obj.makePlotPanel(feedback, ...
                'Force feedback','Time (s)','Force (% MVC)',bg,fg,24);
            forcePanel.Layout.Row = 3;
            xlim(obj.ForceAxes,[0 5]);
            xticks(obj.ForceAxes,0:5);
            ylim(obj.ForceAxes,[-10 80]);
            obj.ForceLines = gobjects(1,3);
            digits = {'Thumb','Index','Middle'};
            for k = 1:3
                obj.ForceLines(k) = plot(obj.ForceAxes,NaN,NaN,'DisplayName',digits{k});
            end
            legend(obj.ForceAxes,obj.ForceLines,'Location','northeast', ...
                'TextColor',fg,'Color',bg,'FontSize',8);
            yline(obj.ForceAxes,0,'-','0% MVC','Color',[0.8 0.8 0.8], ...
                'LineWidth',1.25,'LabelHorizontalAlignment','left', ...
                'LabelVerticalAlignment','bottom','HandleVisibility','off');
            obj.updateForceTarget(cfg);
            obj.AppliedSettings = obj.readSettings();
            obj.updateAxisLabels();
            obj.sync();
            obj.Figure.Visible = 'on';
        end

        function setAvailable(obj,available)
            if obj.Available == available, return; end
            obj.Available = available;
            if available && isempty(obj.LastPhase) && isempty(obj.Capture)
                obj.Status.Text = 'Acquisition ready. Check the reference rates, then start the task.';
            end
            if ~available && ~isempty(obj.Capture)
                obj.Capture = [];
                obj.Status.Text = 'Reference capture cancelled: acquisition stopped or recording started.';
            end
            obj.sync();
        end

        function bindAcquisition(obj,cfg,labels)
            changed = ~isequal(labels,obj.Labels) || ...
                ~isequaln(cfg.quadrantReferenceRates,obj.References) || ...
                ~strcmp(cfg.acquisitionMode,obj.Cfg.acquisitionMode) || ...
                ~strcmp(cfg.decompositionFile,obj.Cfg.decompositionFile);
            obj.Cfg = cfg;
            obj.Labels = labels;
            obj.References = cfg.quadrantReferenceRates;
            obj.ForceTime = zeros(0,1);
            obj.ForceData = zeros(0,3);
            obj.RasterTime = {[],[]};
            obj.LastAuxRefresh = -Inf;
            obj.LastPhase = '';
            obj.resetPreview();
            obj.updateForceTarget(cfg);
            if changed
                for name = {'xMU','yMU'}
                    control = obj.Controls.(name{1});
                    control.ItemsData = [];
                    control.Items = labels;
                    control.ItemsData = 1:numel(labels);
                end
                obj.Controls.xMU.Value = cfg.quadrantXMU;
                obj.Controls.yMU.Value = cfg.quadrantYMU;
                obj.loadReferences();
                obj.AppliedSettings.mu = [cfg.quadrantXMU cfg.quadrantYMU];
                obj.AppliedSettings.muLabels = labels(obj.AppliedSettings.mu);
                obj.AppliedSettings.referencePPS = [obj.Controls.xRef.Value obj.Controls.yRef.Value];
                obj.AppliedSettings.referenceSource = obj.ReferenceSource;
                obj.AppliedSettings.referenceForceMVC = NaN;
                obj.Controls.referenceForce.Value = '';
                obj.updateAxisLabels();
            end
            obj.AppliedSettings.blockDurationSec = cfg.blockDurationSec;
            obj.Controls.rateWindow.Tooltip = sprintf('Acquisition block: %.0f ms. Rates and scoring update once per block.',1000*cfg.blockDurationSec);
            obj.Status.Text = 'Acquisition ready. Check the reference rates, then start the task.';
        end

        function updateFrame(obj,frame)
            pair = obj.AppliedSettings.mu;
            if ~isequal(pair,obj.RasterPair)
                obj.RasterTime = {[],[]};
                obj.RasterPair = pair;
            end
            t = frame.time;
            n = size(frame.spikes,1);
            if n > 0
                times = (frame.sampleCursor-n:frame.sampleCursor-1)/obj.Cfg.fs;
                for k = 1:2
                    allTimes = [obj.RasterTime{k} times(frame.spikes(:,pair(k))~=0)];
                    obj.RasterTime{k} = allTimes(allTimes >= t-5);
                end
                if ~obj.Active
                    obj.updatePreview(frame.spikes(:,pair),pair,t);
                end
            end
            if ~isempty(obj.Capture) && n > 0
                obj.Capture.count = obj.Capture.count+sum(frame.spikes(:,obj.Capture.mu)~=0,1);
                obj.Capture.seconds = obj.Capture.seconds+n/obj.Cfg.fs;
                obj.Status.Text = sprintf('Hold a steady contraction: %.1f / %.1f s', ...
                    obj.Capture.seconds,obj.Capture.goal);
                if obj.Capture.seconds >= obj.Capture.goal-1e-9
                    rates = obj.Capture.count/obj.Capture.seconds;
                    if all(rates>0)
                        obj.Controls.xRef.Value = rates(1);
                        obj.Controls.yRef.Value = rates(2);
                        obj.ReferenceSource = repmat({sprintf('Live capture (%.3f s)',obj.Capture.seconds)},1,2);
                        obj.Status.Text = sprintf('Captured %.2f and %.2f pps. Apply settings to use them.',rates);
                    else
                        obj.Status.Text = 'Capture did not detect firing in both MUs. Previous references retained.';
                    end
                    obj.Capture = [];
                    obj.sync();
                end
            end
            obj.ForceTime = [obj.ForceTime;frame.force.sessionTime];
            obj.ForceData = [obj.ForceData;frame.force.data];
            if ~isempty(obj.ForceTime), t = max(t,obj.ForceTime(end)); end
            keep = obj.ForceTime >= t-5;
            obj.ForceTime = obj.ForceTime(keep);
            obj.ForceData = obj.ForceData(keep,:);
            if t-obj.LastAuxRefresh < 0.1, return; end
            obj.LastAuxRefresh = t;
            for k = 1:3
                set(obj.ForceLines(k),'XData',obj.ForceTime,'YData',obj.ForceData(:,k));
            end
            for k = 1:2
                times = obj.RasterTime{k};
                set(obj.RasterLines(k),'XData',times,'YData',k*ones(size(times)));
            end
            span = [max(0,t-5) max(5,t)];
            xlim(obj.ForceAxes,span); xlim(obj.RasterAxes,span);
            seconds = ceil(span(1)):floor(span(2));
            xticks(obj.ForceAxes,seconds); xticks(obj.RasterAxes,seconds);
        end

        function updateTask(obj,state,settings)
            if ~isgraphics(obj.Figure), return; end
            obj.updateTrialTime(state,settings);
            wasActive = obj.Active;
            obj.Active = isempty(state.completion);
            if obj.Active ~= wasActive, obj.resetPreview(); end
            obj.PreviewStatus.Visible = obj.onOff(~obj.Active);
            targets = MotorUnitTargetTask.Targets;
            set(obj.Cursor,'XData',state.cursor(1),'YData',state.cursor(2));
            set(obj.Trail,'XData',state.trail(:,1),'YData',state.trail(:,2));
            for k = 1:3
                attempting = strcmp(state.phase,'attempt');
                activeTarget = attempting && k==state.target;
                successfulTarget = ~attempting && strcmp(state.lastOutcome,'hit') && k==state.lastTarget;
                obj.TargetShapes(k).Visible = obj.onOff(activeTarget || successfulTarget);
                obj.AngleShapes(k).Visible = obj.onOff(activeTarget);
                if activeTarget || successfulTarget
                    theta = obj.TargetShapes(k).UserData;
                    center = targets(k,:);
                    targetColor = [1 0.2 0.2];
                    if successfulTarget, targetColor = [0.25 0.85 0.45]; end
                    set(obj.TargetShapes(k),'XData',center(1)+settings.targetRadius*cos(theta), ...
                        'YData',center(2)+settings.targetRadius*sin(theta),'Color',targetColor);
                end
                if activeTarget
                    angle = atan2(center(2),center(1));
                    halfAngle = asin(settings.targetRadius/norm(center));
                    a = linspace(angle-halfAngle,angle+halfAngle,30);
                    outer = MotorUnitTargetTask.AxisMax./max(abs([cos(a);sin(a)]),[],1);
                    px = [outer.*cos(a) settings.angleInnerRadius*cos(fliplr(a))];
                    py = [outer.*sin(a) settings.angleInnerRadius*sin(fliplr(a))];
                    set(obj.AngleShapes(k),'XData',px,'YData',py);
                end
            end
            obj.Origin.Visible = obj.onOff(strcmp(state.phase,'rest'));
            theta = linspace(0,2*pi,100);
            set(obj.Origin,'XData',settings.restRadius*cos(theta),'YData',settings.restRadius*sin(theta));
            prefix = sprintf('Trial %d / %d',state.trial,state.total);
            switch state.phase
                case 'rest'
                    message = sprintf('%s  |  Relax at the origin: %.2f / %.2f s', ...
                        prefix,state.restHeld,settings.restTime);
                    if strcmp(state.lastOutcome,'hit')
                        message = [message '  |  Previous: target hit'];
                    elseif state.lastAngleHit
                        message = [message '  |  Previous: angle hit'];
                    elseif ~isempty(state.lastOutcome)
                        message = [message '  |  Previous: ' state.lastOutcome];
                    end
                case 'attempt'
                    names = MotorUnitTargetTask.TargetNames;
                    message = sprintf('%s  |  %s  |  %.1f s left\nTarget hold: %.2f / %.2f s     Angle hold: %.2f / %.2f s', ...
                        prefix,names{state.target},state.remaining,state.targetHeld,settings.targetHold, ...
                        state.angleHeld,settings.angleHold);
                    if state.angleHit, message = [message ' (hit)']; end
                otherwise
                    message = sprintf('Task %s. Results are in Completed recordings.',state.completion);
            end
            if obj.Active && strcmp(obj.Cfg.acquisitionMode,'Simulation')
                message = [message '  |  Simulation follows the cues'];
            end
            obj.Status.Text = message;
            if obj.Active ~= wasActive, obj.sync(); end
            if ~strcmp(obj.LastPhase,state.phase)
                obj.LastPhase = state.phase;
                drawnow nocallbacks;
            else
                drawnow limitrate nocallbacks;
            end
        end

        function delete(obj)
            if isgraphics(obj.Figure), delete(obj.Figure); end
        end
    end
    methods (Access=private)
        function updateForceTarget(obj,cfg)
            delete(findall(obj.ForceAxes,'Tag','taskForceTarget'));
            if cfg.showForceTarget
                yline(obj.ForceAxes,cfg.forceTargetMVC,'--', ...
                    sprintf('Target: %g%% MVC',cfg.forceTargetMVC), ...
                    'Color',[1 0.85 0.2],'LineWidth',1.5, ...
                    'LabelHorizontalAlignment','right','LabelVerticalAlignment','top', ...
                    'HandleVisibility','off','Tag','taskForceTarget');
            end
        end

        function updateTrialTime(obj,state,settings)
            switch state.phase
                case 'attempt'
                    duration = settings.timeout;
                    remaining = state.remaining;
                    label = 'Trial time left';
                    targets = MotorUnitTargetTask.Targets;
                    if norm(state.cursor-targets(state.target,:)) <= settings.targetRadius
                        obj.TaskInstruction.Text = 'Hold the cursor inside the target circle.';
                    else
                        obj.TaskInstruction.Text = 'Move the cursor to the target circle.';
                    end
                case 'rest'
                    duration = settings.restTime;
                    remaining = duration-state.restHeld;
                    label = 'Rest at origin time left';
                    obj.TaskInstruction.Text = 'Return to the origin and rest inside the blue circle.';
                otherwise
                    obj.TaskInstruction.Text = 'Task ended. Relax at the origin.';
                    obj.TrialTimeLabel.Text = 'Trial time left: —';
                    obj.TrialTimeFill.Visible = 'off';
                    return;
            end
            remaining = max(0,min(duration,remaining));
            fraction = remaining/duration;
            obj.TrialTimeLabel.Text = sprintf('%s: %.1f / %.1f s',label,remaining,duration);
            obj.TrialTimeBar.ColumnWidth = {sprintf('%.6gx',max(fraction,0.001)), ...
                sprintf('%.6gx',max(1-fraction,0.001))};
            obj.TrialTimeFill.Visible = obj.onOff(remaining>0);
        end

        function resetPreview(obj)
            obj.PreviewSettings = [];
            obj.PreviewRates = [];
            obj.PreviewTimes = [];
            obj.PreviewTrail = zeros(0,2);
        end

        function updatePreview(obj,spikes,pair,t)
            s = obj.AppliedSettings;
            ref = s.referencePPS;
            gain = s.gain;
            window = s.rateWindow;
            smoothing = s.smoothing;
            values = [pair ref gain window smoothing];
            if pair(1)==pair(2) || any(~isfinite(values) | values<=0) || smoothing~=fix(smoothing)
                obj.resetPreview();
                set(obj.Cursor,'XData',NaN,'YData',NaN);
                set(obj.Trail,'XData',NaN,'YData',NaN);
                obj.PreviewStatus.Text = 'Preview: choose distinct MUs and valid rates, gains and smoothing.';
                return;
            end
            if ~isequal(values,obj.PreviewSettings)
                obj.resetPreview();
                obj.PreviewSettings = values;
            end
            dt = size(spikes,1)/obj.Cfg.fs;
            [obj.PreviewRates,~,rate] = MotorUnitTargetTask.estimateRates( ...
                obj.PreviewRates,spikes,dt,window,smoothing);
            p = rate./ref.*gain;
            obj.PreviewTimes(end+1) = t;
            obj.PreviewTrail(end+1,:) = p;
            keep = obj.PreviewTimes>=t-s.cursorHistory;
            obj.PreviewTimes = obj.PreviewTimes(keep);
            obj.PreviewTrail = obj.PreviewTrail(keep,:);
            set(obj.Cursor,'XData',p(1),'YData',p(2));
            set(obj.Trail,'XData',obj.PreviewTrail(:,1),'YData',obj.PreviewTrail(:,2));
            obj.PreviewStatus.Text = sprintf('Live preview  |  X: %.1f pps   Y: %.1f pps',rate);
            if any(p>MotorUnitTargetTask.AxisMax)
                obj.PreviewStatus.Text = [obj.PreviewStatus.Text '  |  Cursor outside plot range'];
            end
        end

        function start(obj)
            try
                assert(isequaln(obj.readSettings(),obj.AppliedSettings), ...
                    'Press Apply settings before starting the task.');
                obj.OnStart(obj.AppliedSettings);
            catch exception
                uialert(obj.Figure,exception.message,'Cannot start task');
            end
        end

        function applySettings(obj)
            try
                assert(~obj.Active && isempty(obj.Capture),'Stop the task or reference capture first.');
                settings = obj.readSettings();
                MotorUnitTargetTask(settings,1); % Validate the settings even before acquisition.
                obj.AppliedSettings = settings;
                set(obj.ReferenceLines,'Visible',obj.onOff(settings.showReferenceLines));
                set(obj.TargetShapes,'Visible','off');
                obj.updateAxisLabels();
                obj.resetPreview();
                set(obj.Cursor,'XData',NaN,'YData',NaN);
                set(obj.Trail,'XData',NaN,'YData',NaN);
                theta = linspace(0,2*pi,100);
                set(obj.Origin,'XData',settings.restRadius*cos(theta), ...
                    'YData',settings.restRadius*sin(theta),'Visible','on');
                obj.Status.Text = 'Settings applied. Start acquisition and the task when ready.';
            catch exception
                uialert(obj.Figure,exception.message,'Cannot apply settings');
            end
        end

        function resetSettings(obj)
            if obj.Active || ~isempty(obj.Capture), return; end
            defaults = obj.Defaults;
            defaults.xMU = obj.Cfg.quadrantXMU;
            defaults.yMU = obj.Cfg.quadrantYMU;
            for name = fieldnames(defaults)'
                obj.Controls.(name{1}).Value = defaults.(name{1});
            end
            obj.loadReferences();
            obj.Status.Text = 'Default values restored. Press Apply settings to use them.';
        end

        function settings = readSettings(obj)
                settings = struct();
                for name = {'experimentNotes','targetRadius','angleInnerRadius', ...
                        'targetHold','angleHold','timeout','restTime','restRadius', ...
                        'repetitions','randomize','seed','rateWindow','smoothing','cursorHistory','showReferenceLines'}
                    settings.(name{1}) = obj.Controls.(name{1}).Value;
                end
                settings.mu = [obj.Controls.xMU.Value obj.Controls.yMU.Value];
                settings.muLabels = obj.Labels(settings.mu);
                settings.referencePPS = [obj.Controls.xRef.Value obj.Controls.yRef.Value];
                settings.referenceSource = obj.ReferenceSource;
                settings.referenceForceMVC = NaN;
                forceText = strtrim(obj.Controls.referenceForce.Value);
                if ~isempty(forceText)
                    settings.referenceForceMVC = str2double(forceText);
                    validateattributes(settings.referenceForceMVC,{'numeric'},{'scalar','finite','>=',0,'<=',100});
                end
                settings.gain = [obj.Controls.xGain.Value obj.Controls.yGain.Value];
                settings.blockDurationSec = obj.Cfg.blockDurationSec;
        end

        function startCapture(obj)
            try
                assert(obj.Available && ~obj.Active,'Start acquisition and stop any recording first.');
                assert(obj.Controls.xMU.Value ~= obj.Controls.yMU.Value,'Choose two different motor units.');
                goal = obj.Controls.captureSec.Value;
                validateattributes(goal,{'numeric'},{'scalar','positive','finite'});
                obj.Capture = struct('goal',goal,'seconds',0,'count',[0 0], ...
                    'mu',[obj.Controls.xMU.Value obj.Controls.yMU.Value]);
                obj.Status.Text = 'Hold the reference contraction steadily. Capturing now...';
                obj.sync();
            catch exception
                uialert(obj.Figure,exception.message,'Cannot capture reference');
            end
        end

        function loadReferences(obj)
            pair = [obj.Controls.xMU.Value obj.Controls.yMU.Value];
            values = obj.References(pair);
            values(~isfinite(values) | values<=0) = 0;
            obj.Controls.xRef.Value = values(1);
            obj.Controls.yRef.Value = values(2);
            if strcmp(obj.Cfg.acquisitionMode,'Simulation')
                obj.ReferenceSource = {'Simulated reference','Simulated reference'};
            else
                obj.ReferenceSource = {'Imported calibration reference','Imported calibration reference'};
            end
        end

        function updateAxisLabels(obj)
            identities = obj.AppliedSettings.muLabels;
            xlabel(obj.TaskAxes,['Activity of motor unit 1 (normalised) : ' identities{1}], ...
                'FontSize',18,'FontWeight','bold');
            ylabel(obj.TaskAxes,['Activity of motor unit 2 (normalised) : ' identities{2}], ...
                'FontSize',18,'FontWeight','bold');
        end

        function markManual(obj,axisIndex)
            obj.ReferenceSource{axisIndex} = 'Entered manually';
        end

        function sync(obj)
            editable = ~obj.Active && isempty(obj.Capture);
            for name = fieldnames(obj.Controls)'
                obj.Controls.(name{1}).Enable = obj.onOff(editable);
            end
            obj.StartButton.Enable = obj.onOff(editable && obj.Available);
            obj.CaptureButton.Enable = obj.onOff(editable && obj.Available);
            obj.ApplyButton.Enable = obj.onOff(editable);
            obj.ResetButton.Enable = obj.onOff(editable);
            obj.StopButton.Enable = obj.onOff(obj.Active);
        end

        function close(obj)
            if obj.Active, obj.OnStop(); end
            delete(obj);
        end
    end
    methods (Static,Access=private)
        function [ax,panel] = makePlotPanel(parent,name,x,y,bg,fg,headingHeight)
            panel = uipanel(parent,'BorderType','line','HighlightColor',[0.4 0.4 0.4], ...
                'BackgroundColor',bg);
            grid = uigridlayout(panel,[2 1],'RowHeight',{headingHeight,'1x'}, ...
                'Padding',[4 2 4 2],'RowSpacing',2,'BackgroundColor',bg);
            uilabel(grid,'Text',name,'FontWeight','bold','FontColor',fg,'WordWrap','on', ...
                'HorizontalAlignment','center');
            ax = ExperimentalTaskWindow.makeAxes(grid,x,y);
        end

        function ax = makeAxes(parent,x,y)
            ax = uiaxes(parent,'Color',[0.1 0.1 0.1],'XColor',[0.9 0.9 0.9], ...
                'YColor',[0.9 0.9 0.9],'GridColor',[0.5 0.5 0.5]);
            xlabel(ax,x); ylabel(ax,y); grid(ax,'on'); hold(ax,'on');
        end

        function value = onOff(flag)
            value = 'off';
            if flag, value = 'on'; end
        end
    end
end
