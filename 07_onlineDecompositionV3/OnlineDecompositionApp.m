classdef OnlineDecompositionApp < handle
    %ONLINEDECOMPOSITIONAPP Multi-grid acquisition, feedback and recording app.
    %   app = OnlineDecompositionApp;

    properties (SetAccess = private)
        Figure
        DecompositionFile = ''
        ForceCalibrationFile = ''
        CalibrationData = struct()
        Parameters = struct()
        ForceCalibration = struct()
        Recordings = {}
        SavedFiles = {}
        LastResults = struct()
    end

    properties (Access = private)
        DecompositionLabel
        DecompositionSummary
        ForceLabel
        ForceSummary
        Inputs = struct()
        QuadrantSettings = struct('showQuadrant',true,'quadrantXMU',1, ...
            'quadrantYMU',2,'quadrantRateWindowSec',1, ...
            'quadrantSmoothingWindows',4,'quadrantHistorySec',7.5,'quadrantAxisMax',[], ...
            'quadrantAxisScale',1.5, ...
            'quadrantShowReferenceLines',true)
        Session = []
        Dashboard
        TaskWindow = []
        ImportButtons
        Mode
        StartButton
        StopButton
        RecordButton
        StopRecordButton
        ZeroButton
        SaveButton
        RecordingSelector
        StatusLabel
        Participant
        SessionNumber
        TrialNumber
        AutoSave
        OutputFolder
        BrowseButton
        ChannelButton
        Busy = false
    end

    methods
        function app = OnlineDecompositionApp()
            background = [0.96 0.955 0.94];
            foreground = [0.12 0.12 0.12];
            app.Figure = uifigure('Name','Online EMG decomposition with biofeedback', ...
                'Position',[60 60 1480 880],'Color',background, ...
                'CloseRequestFcn',@(~,~) app.closeApp());
            layout = uigridlayout(app.Figure,[1 2], ...
                'ColumnWidth',{440,'1x'},'Padding',[0 0 0 0], ...
                'ColumnSpacing',0,'BackgroundColor',background);
            sidebar = uipanel(layout,'BackgroundColor',background, ...
                'BorderType','line','HighlightColor',[0.7 0.7 0.7]);
            controls = uigridlayout(sidebar,[9 1], ...
                'RowHeight',{36,40,30,44,8,40,30,30,'1x'}, ...
                'Padding',[12 10 12 10],'RowSpacing',8, ...
                'BackgroundColor',background);
            uilabel(controls,'Text','BIOFEEDBACK','FontSize',22, ...
                'FontWeight','bold','FontColor',foreground);
            app.ImportButtons = uibutton(controls,'Text','Load MU filter', ...
                'BackgroundColor',[0.45 0.22 0.65], ...
                'FontColor',[1 1 1],'FontSize',15,'FontWeight','bold', ...
                'ButtonPushedFcn',@(~,~) app.importDecomposition());
            app.DecompositionLabel = uilabel(controls, ...
                'Text','No MU filter file selected','WordWrap','on', ...
                'FontColor',foreground);
            app.DecompositionSummary = uilabel(controls, ...
                'Text','','WordWrap','on','VerticalAlignment','top', ...
                'FontColor',[0.35 0.35 0.35]);
            uilabel(controls,'Text','');
            app.ImportButtons(2) = uibutton(controls,'Text','Load Force Calibration file', ...
                'BackgroundColor',[0.45 0.22 0.65], ...
                'FontColor',[1 1 1],'FontSize',15,'FontWeight','bold', ...
                'ButtonPushedFcn',@(~,~) app.importForceCalibration());
            app.ForceLabel = uilabel(controls, ...
                'Text','No Force Calibration file selected','WordWrap','on', ...
                'FontColor',foreground);
            app.ForceSummary = uilabel(controls, ...
                'Text','','WordWrap','on','FontColor',[0.35 0.35 0.35]);
            app.createSettings(controls);
            app.createWorkspace(layout);
            app.syncControls();
        end

        function delete(app)
            if ~isempty(app.Session) && isvalid(app.Session)
                try
                    app.Session.stop();
                catch
                end
                app.Session.OnStatus = [];
                app.Session.OnUpdate = [];
                app.Session.OnRecording = [];
                app.Session.OnError = [];
                delete(app.Session);
            end
            if ~isempty(app.Dashboard) && isvalid(app.Dashboard), delete(app.Dashboard); end
            if ~isempty(app.TaskWindow) && isvalid(app.TaskWindow), delete(app.TaskWindow); end
            if ~isempty(app.Figure) && isgraphics(app.Figure)
                delete(app.Figure);
            end
        end

        function cfg = getConfig(app)
            % Read UI settings into the same cfg structure as the launcher.
            setup_online_dependencies();
            values = struct('showLegend',true,'frYLim',60,'forceBufferTimeSec',0);
            names = fieldnames(app.Inputs);
            for idx = 1:numel(names)
                name = names{idx};
                input = app.Inputs.(name);
                value = input.Value;
                if (ischar(value) || isstring(value)) && ...
                        ~strcmp(name,'forcePort')
                    value = app.parseNumbers(value);
                end
                values.(name) = value;
            end
            extra = fieldnames(app.QuadrantSettings);
            for idx = 1:numel(extra)
                values.(extra{idx}) = app.QuadrantSettings.(extra{idx});
            end
            names = fieldnames(values);
            validateattributes(values.numberOfGrids,{'numeric'}, ...
                {'scalar','integer','>=',1,'<=',10});
            nGrids = values.numberOfGrids;
            validateattributes(values.activeInputs,{'numeric'}, ...
                {'vector','numel',nGrids,'integer','>=',1,'<=',10});
            assert(numel(unique(values.activeInputs)) == nGrids, ...
                'Active inputs must be distinct.');
            for name = {'calibChannels','emgChannels'}
                validateattributes(values.(name{1}),{'numeric'}, ...
                    {'vector','numel',64*nGrids,'integer','positive','finite'});
                assert(numel(unique(values.(name{1}))) == 64*nGrids, ...
                    '%s must not contain duplicate channels.',name{1});
            end
            assert(isequal(sort(values.calibChannels),1:64*nGrids), ...
                'Calibration channels must include all electrodes exactly once.');
            validateattributes(values.emgPreviewChannels,{'numeric'}, ...
                {'vector','nonempty','integer','positive','finite','<=',64*nGrids});
            assert(numel(unique(values.emgPreviewChannels)) == numel(values.emgPreviewChannels), ...
                'EMG preview channels must not contain duplicates.');
            validateattributes(values.forceInputChannelCounts,{'numeric'}, ...
                {'vector','numel',10,'integer','nonnegative','finite'});
            assert(values.blockDurationSec > 0 && ...
                abs(values.blockDurationSec*500-round(values.blockDurationSec*500)) < 1e-9, ...
                'EMG window must be a positive multiple of 0.002 seconds.');
            validateattributes(values.onlineDurationSec,{'numeric'}, ...
                {'scalar','positive','nonnan'});
            if ~isempty(fieldnames(app.CalibrationData)) && ...
                    ~strcmp(app.Mode.Value,'Simulation')
                assert(numel(app.CalibrationData.EMGmask) == nGrids, ...
                    'Number of grids does not match the imported decomposition.');
            end
            cfg = makeNovecentoConfig(values.blockDurationSec, ...
                values.activeInputs,values.emgChannels);
            for idx = 1:numel(names)
                cfg.(names{idx}) = values.(names{idx});
            end
            cfg.windowBaseCols = round(values.blockDurationSec*500);
            cfg.forceCalibrationFile = app.ForceCalibrationFile;
            cfg.decompositionFile = app.DecompositionFile;
            if strcmp(app.Mode.Value,'Simulation')
                cfg.quadrantReferenceRates = 12+2*(0:3*nGrids-1);
            elseif ~isempty(fieldnames(app.CalibrationData))
                cfg.quadrantReferenceRates = get_mu_reference_rates(app.CalibrationData);
            else
                cfg.quadrantReferenceRates = [];
            end
            for name = {'forceFs','forceDisplayTimeSec', ...
                    'forcePlotRateHz','visibleWindowSec','frYLim', ...
                    'quadrantRateWindowSec','quadrantHistorySec','quadrantAxisScale'}
                validateattributes(cfg.(name{1}),{'numeric'}, ...
                    {'scalar','positive','finite'});
            end
            for name = {'quadrantXMU','quadrantYMU','quadrantSmoothingWindows'}
                validateattributes(cfg.(name{1}),{'numeric'}, ...
                    {'scalar','integer','positive','finite'});
            end
            validateattributes(cfg.printEveryNWindows,{'numeric'}, ...
                {'scalar','integer','nonnegative','finite'});
            validateattributes(cfg.forceBufferTimeSec,{'numeric'}, ...
                {'scalar','nonnegative','finite'});
            validateattributes(cfg.forceTargetMVC,{'numeric'}, ...
                {'scalar','finite','>=',0,'<=',100});
            if ~isempty(cfg.quadrantAxisMax)
                validateattributes(cfg.quadrantAxisMax,{'numeric'}, ...
                    {'scalar','positive','finite'});
            end
            if cfg.showQuadrant
                assert(cfg.quadrantXMU ~= cfg.quadrantYMU, ...
                    'Quadrant X and Y must select different MUs.');
            end
            assert(~isempty(strtrim(cfg.forcePort)), 'Enter the Arduino serial port.');
            validateattributes(cfg.forceDefaultCalibrationFactors,{'numeric'}, ...
                {'vector','numel',3,'nonzero','finite'});
            validateattributes(cfg.forceDefaultZeroValues,{'numeric'}, ...
                {'vector','numel',3,'finite'});
            validateattributes(cfg.forceDefaultReverseStates,{'numeric','logical'}, ...
                {'vector','numel',3,'binary'});
            cfg.forceDefaultReverseStates = logical(cfg.forceDefaultReverseStates);
            cfg.acquisitionMode = app.Mode.Value;
            cfg.decompositionFile = app.DecompositionFile;
            cfg.forceCalibration = app.ForceCalibration;
            if isempty(fieldnames(cfg.forceCalibration))
                cfg.forceCalibration = struct( ...
                    'calibrationFactors',cfg.forceDefaultCalibrationFactors, ...
                    'zeroValues',cfg.forceDefaultZeroValues, ...
                    'reverseStates',cfg.forceDefaultReverseStates);
            end
            for name = {'calibrationFactors','zeroValues','reverseStates'}
                cfg.forceCalibration.(name{1}) = reshape(cfg.forceCalibration.(name{1}),1,[]);
            end
        end

        function loadDecomposition(app,file)
            % Programmatic equivalent of the import button.
            assert(isempty(app.Session) || ~app.Session.Running, ...
                'Stop acquisition before replacing calibration.');
            app.importDecomposition(char(file));
        end

        function loadForceCalibration(app,file)
            assert(isempty(app.Session) || ~app.Session.Running, ...
                'Stop acquisition before replacing force calibration.');
            app.importForceCalibration(char(file));
        end
    end

    methods (Access = private)
        function createWorkspace(app,parent)
            workspace = uigridlayout(parent,[6 1], ...
                'RowHeight',{36,30,30,'1x',36,32}, ...
                'RowSpacing',8, ...
                'BackgroundColor',[0.96 0.955 0.94]);
            toolbar = uigridlayout(workspace,[1 7], ...
                'ColumnWidth',{160,140,140,140,140,90,'1x'}, ...
                'ColumnSpacing',8,'Padding',[0 0 0 0]);
            app.Mode = uidropdown(toolbar, ...
                'Items',{'Simulation','Replay calibration','Hardware'}, ...
                'Value','Simulation','Tag','acquisitionMode', ...
                'Tooltip','Simulation: synthetic signals. Replay: stored EMG through I-Spin and recorded force when available (otherwise simulated). Hardware: live EMG and force.');
            app.Mode.ValueChangedFcn = @(~,~) app.refreshMuChoices();
            app.StartButton = uibutton(toolbar,'Text','Start acquisition', ...
                'BackgroundColor',[0.1 0.4 0.8],'FontColor',[1 1 1], ...
                'ButtonPushedFcn',@(~,~) app.startAcquisition());
            app.StopButton = uibutton(toolbar,'Text','Stop acquisition', ...
                'BackgroundColor',[0.5 0.5 0.5],'FontColor',[1 1 1], ...
                'ButtonPushedFcn',@(~,~) app.stopAcquisition());
            app.RecordButton = uibutton(toolbar,'Text','Start recording', ...
                'BackgroundColor',[0.2 0.55 0.3],'FontColor',[1 1 1], ...
                'ButtonPushedFcn',@(~,~) app.startRecording());
            app.StopRecordButton = uibutton(toolbar,'Text','Stop recording', ...
                'BackgroundColor',[0.8 0.15 0.15],'FontColor',[1 1 1], ...
                'ButtonPushedFcn',@(~,~) app.stopRecording());
            app.ZeroButton = uibutton(toolbar,'Text','Zero force', ...
                'ButtonPushedFcn',@(~,~) app.zeroForce());
            metadata = uigridlayout(workspace,[1 9], ...
                'ColumnWidth',{90,140,55,65,40,65,75,60,'1x'}, ...
                'ColumnSpacing',8,'Padding',[0 0 0 0]);
            uilabel(metadata,'Text','Participant');
            app.Participant = uieditfield(metadata,'Value','P001');
            uilabel(metadata,'Text','Session');
            app.SessionNumber = uieditfield(metadata,'numeric','Value',1, ...
                'Limits',[1 Inf],'RoundFractionalValues','on');
            uilabel(metadata,'Text','Trial');
            app.TrialNumber = uieditfield(metadata,'numeric','Value',1, ...
                'Limits',[1 Inf],'RoundFractionalValues','on');
            uilabel(metadata,'Text','Auto-save');
            app.AutoSave = uicheckbox(metadata,'Text','On','Value',true,'Tag','autoSave');
            output = uigridlayout(workspace,[1 4], ...
                'ColumnWidth',{90,480,80,'1x'},'ColumnSpacing',8,'Padding',[0 0 0 0]);
            uilabel(output,'Text','Output folder');
            root = fileparts(fileparts(mfilename('fullpath')));
            app.OutputFolder = uieditfield(output,'Value',fullfile(root,'online_results'), ...
                'Tag','outputFolder');
            app.BrowseButton = uibutton(output,'Text','Browse', ...
                'ButtonPushedFcn',@(~,~) app.browseOutput());
            app.Dashboard = OnlineAppDashboard(workspace);
            app.Dashboard.OnQuadrantSettingsChanged = @(settings) app.updateQuadrantSettings(settings);
            app.Dashboard.OnOpenExperimentalTask = @() app.openExperimentalTask();
            completed = uigridlayout(workspace,[1 3], ...
                'ColumnWidth',{140,'1x',140},'Padding',[0 0 0 0]);
            uilabel(completed,'Text','Completed recordings');
            app.RecordingSelector = uidropdown(completed,'Items',{'None'},'Enable','off');
            app.SaveButton = uibutton(completed,'Text','Save selected...', ...
                'ButtonPushedFcn',@(~,~) app.saveSelected());
            app.StatusLabel = uilabel(workspace,'Text', ...
                'Ready. Simulation needs no hardware or imported files.', ...
                'FontColor',[0.15 0.35 0.2],'WordWrap','on','Tag','acquisitionStatus');
            % Style all settings and toolbars consistently with the reference.
            labels = findall(workspace,'Type','uilabel');
            for item = labels', item.FontColor = [0.12 0.12 0.12]; end
            grids = findall(workspace,'Type','uigridlayout');
            for item = grids', item.BackgroundColor = [0.96 0.955 0.94]; end
        end

        function updateQuadrantSettings(app,settings)
            if ~isempty(app.Session) && isvalid(app.Session)
                app.Session.setQuadrantSettings(settings);
            end
            names = fieldnames(settings);
            for idx = 1:numel(names)
                app.QuadrantSettings.(names{idx}) = settings.(names{idx});
            end
            app.setStatus('Quadrant settings applied.');
        end

        function startAcquisition(app)
            if app.Busy, return; end
            app.Busy = true;
            app.syncControls();
            cleanup = onCleanup(@() app.endBusy());
            try
                if strcmp(app.Mode.Value,'Hardware') && ...
                        isempty(app.ForceCalibrationFile) && app.Inputs.forcePromptCalibration.Value
                    app.importForceCalibration();
                end
                cfg = app.getConfig();
                app.setStatus('Preparing acquisition...');
                drawnow;
                if ~isempty(app.Session), delete(app.Session); end
                app.Session = OnlineAcquisitionSession(cfg,app.CalibrationData,app.Parameters);
                app.Session.OnStatus = @(message) app.setStatus(message);
                app.Session.OnRecording = @(result) app.recordingCompleted(result);
                app.Session.OnError = @(exception) app.sessionError(exception);
                app.Session.start(false);
                app.Dashboard.initialize(app.Session.Config,app.Session.Labels);
                app.Session.OnUpdate = @(frame) app.updateFeedback(frame);
                app.Session.OnTaskUpdate = @(state,settings) app.updateExperimentalTask(state,settings);
                if app.hasTaskWindow()
                    if numel(app.Session.Labels)>=2
                        app.TaskWindow.bindAcquisition(app.Session.Config,app.Session.Labels);
                    else
                        delete(app.TaskWindow);
                    end
                end
                app.Session.beginPolling();
                app.setStatus([cfg.acquisitionMode ': acquisition running; recording is OFF.']);
            catch exception
                if ~isempty(app.Session), app.Session.stop(); end
                app.sessionError(exception);
            end
        end

        function stopAcquisition(app)
            try
                if ~isempty(app.Session), app.Session.stop(); end
            catch exception
                app.sessionError(exception);
            end
            app.syncControls();
        end

        function startRecording(app)
            try
                app.Session.startRecording(app.recordingMetadata());
                app.setStatus('RECORDING — use Stop recording to finish this segment.');
            catch exception
                app.sessionError(exception);
            end
            app.syncControls();
        end

        function metadata = recordingMetadata(app)
            metadata = struct('participant',strtrim(app.Participant.Value), ...
                'session',app.SessionNumber.Value,'trial',app.TrialNumber.Value, ...
                'decompositionFile',app.DecompositionFile, ...
                'forceCalibrationFile',app.ForceCalibrationFile);
            assert(~isempty(metadata.participant),'Enter a participant ID.');
            validateattributes(metadata.session,{'numeric'},{'scalar','integer','positive','finite'});
            validateattributes(metadata.trial,{'numeric'},{'scalar','integer','positive','finite'});
            if app.AutoSave.Value, app.ensureOutputFolder(); end
        end

        function openExperimentalTask(app)
            if app.hasTaskWindow(), app.TaskWindow.show(); return; end
            try
                if ~isempty(app.Session) && isvalid(app.Session) && app.Session.Running
                    cfg = app.Session.Config;
                    labels = app.Session.Labels;
                else
                    cfg = app.getConfig();
                    if strcmp(cfg.acquisitionMode,'Simulation')
                        counts = repmat(3,1,cfg.numberOfGrids);
                    elseif ~isempty(cfg.quadrantReferenceRates)
                        counts = cellfun(@(p) size(p,1),app.CalibrationData.Pulsetrain);
                    else
                        error('Load an MU filter file or select Simulation.');
                    end
                    labels = {};
                    for g = 1:numel(counts)
                        labels = [labels arrayfun(@(m) sprintf('G%d MU%d',g,m), ...
                            1:counts(g),'UniformOutput',false)]; %#ok<AGROW>
                    end
                end
                assert(numel(labels)>=2,'Experimental task requires at least two motor units.');
                app.TaskWindow = ExperimentalTaskWindow(cfg,labels, ...
                    @(settings) app.startExperimentalTask(settings),@() app.stopRecording());
                app.syncControls();
            catch exception
                uialert(app.Figure,exception.message,'Experimental task');
            end
        end

        function startExperimentalTask(app,settings)
            assert(~app.Busy && ~isempty(app.Session) && app.Session.Running && ~app.Session.Recording, ...
                'Start acquisition and stop any active recording first.');
            app.Session.startExperimentalTask(settings,app.recordingMetadata());
            app.syncControls();
        end

        function updateFeedback(app,frame)
            if app.hasTaskWindow(), app.TaskWindow.updateFrame(frame); end
            app.Dashboard.update(frame);
        end

        function updateExperimentalTask(app,state,settings)
            if app.hasTaskWindow(), app.TaskWindow.updateTask(state,settings); end
        end

        function yes = hasTaskWindow(app)
            yes = ~isempty(app.TaskWindow) && isvalid(app.TaskWindow) && app.TaskWindow.isOpen();
        end

        function stopRecording(app)
            try
                app.Session.stopRecording();
            catch exception
                app.sessionError(exception);
            end
            app.syncControls();
        end

        function zeroForce(app)
            try
                app.Session.zeroForce();
            catch exception
                app.sessionError(exception);
            end
        end

        function recordingCompleted(app,result)
            app.Recordings{end+1} = result;
            app.SavedFiles{end+1} = '';
            app.LastResults = result;
            labels = cell(1,numel(app.Recordings));
            for idx = 1:numel(labels)
                recording = app.Recordings{idx};
                labels{idx} = sprintf('%d: %s / session %d / trial %d (%.2f s)', ...
                    idx,recording.metadata.participant,recording.metadata.session, ...
                    recording.metadata.trial,recording.elapsedSec);
            end
            app.RecordingSelector.ItemsData = [];
            app.RecordingSelector.Items = labels;
            app.RecordingSelector.ItemsData = 1:numel(labels);
            app.RecordingSelector.Value = numel(labels);
            app.TrialNumber.Value = app.TrialNumber.Value+1;
            if app.AutoSave.Value
                try
                    file = app.saveRecording(numel(labels),'');
                    app.setStatus(['Recording saved: ' file]);
                catch exception
                    app.setStatus(['Save failed; recording retained in app: ' exception.message]);
                    uialert(app.Figure,exception.message,'Recording needs saving');
                end
            else
                app.setStatus('Recording finished; retained in app. Use Save selected to write a MAT file.');
            end
            app.syncControls();
        end

        function saveSelected(app)
            idx = app.RecordingSelector.Value;
            try
                app.ensureOutputFolder();
                [name,folder] = uiputfile('*.mat','Save online recording', ...
                    app.defaultOutputName(idx));
                if isequal(name,0), return; end
                app.saveRecording(idx,fullfile(folder,name));
                app.setStatus(['Saved: ' app.SavedFiles{idx}]);
            catch exception
                app.sessionError(exception);
            end
        end

        function file = saveRecording(app,idx,file)
            if isempty(file)
                app.ensureOutputFolder();
                file = app.defaultOutputName(idx);
            end
            recording = app.Recordings{idx};
            variable = 'data_out';
            if isfield(recording,'task'), variable = 'task_data'; end
            payload = struct(variable,recording);
            % Write a temporary file, then move it so failed writes leave prior files intact.
            folder = fileparts(file);
            temporary = [tempname(folder) '.mat'];
            cleanup = onCleanup(@() app.removeTemporary(temporary));
            save(temporary,'-struct','payload','-v7.3');
            [ok,message] = movefile(temporary,file,'f');
            assert(ok,'%s',message);
            app.SavedFiles{idx} = file;
        end

        function file = defaultOutputName(app,idx)
            recording = app.Recordings{idx};
            metadata = recording.metadata;
            participant = regexprep(metadata.participant,'[^a-zA-Z0-9_-]','_');
            if isfield(recording,'task')
                base = sprintf('%s_s%d_t%d_task',participant,metadata.session,metadata.trial);
            else
                stamp = char(datetime('now','Format','yyyyMMdd_HHmmss_SSS'));
                base = sprintf('%s_s%d_t%d_%s_online',participant, ...
                    metadata.session,metadata.trial,stamp);
            end
            file = fullfile(app.OutputFolder.Value,[base '.mat']);
            suffix = 1;
            while isfile(file)
                file = fullfile(app.OutputFolder.Value,sprintf('%s_%d.mat',base,suffix));
                suffix = suffix+1;
            end
        end

        function ensureOutputFolder(app)
            folder = strtrim(app.OutputFolder.Value);
            assert(~isempty(folder),'Choose an output folder.');
            if ~isfolder(folder)
                [ok,message] = mkdir(folder); assert(ok,'%s',message);
            end
            [ok,attributes] = fileattrib(folder);
            assert(ok,'Cannot resolve output folder.');
            app.OutputFolder.Value = attributes.Name;
        end

        function browseOutput(app)
            folder = uigetdir(pwd,'Choose online recording folder');
            if ~isequal(folder,0), app.OutputFolder.Value = folder; end
        end

        function setStatus(app,message)
            if ~isgraphics(app.Figure), return; end
            app.StatusLabel.Text = message;
            app.syncControls();
        end

        function sessionError(app,exception)
            fprintf(2,'%s\n',getReport(exception,'extended','hyperlinks','off'));
            app.setStatus(['Error: ' exception.message]);
            if isgraphics(app.Figure), uialert(app.Figure,exception.message,'Online acquisition'); end
            app.syncControls();
        end

        function endBusy(app)
            app.Busy = false;
            if isgraphics(app.Figure), app.syncControls(); end
        end

        function syncControls(app)
            running = ~isempty(app.Session) && isvalid(app.Session) && app.Session.Running;
            recording = running && app.Session.Recording;
            idle = ~running && ~app.Busy;
            app.Dashboard.setRecordingLocked(recording || app.Busy);
            if app.hasTaskWindow(), app.TaskWindow.setAvailable(running && ~recording && ~app.Busy); end
            app.StartButton.Enable = app.enabled(idle);
            app.StopButton.Enable = app.enabled(running && ~app.Busy);
            app.RecordButton.Enable = app.enabled(running && ~recording && ~app.Busy);
            app.StopRecordButton.Enable = app.enabled(recording);
            recordedReplayForce = running && isfield(app.Session.Config,'forceSource') && ...
                strcmp(app.Session.Config.forceSource,'recorded');
            app.ZeroButton.Enable = app.enabled(running && ~recording && ~recordedReplayForce);
            app.Mode.Enable = app.enabled(idle);
            names = fieldnames(app.Inputs);
            for idx = 1:numel(names), app.Inputs.(names{idx}).Enable = app.enabled(idle); end
            app.ChannelButton.Enable = app.enabled(idle);
            for button = app.ImportButtons, button.Enable = app.enabled(idle); end
            metadataControls = {app.Participant,app.SessionNumber,app.TrialNumber, ...
                app.AutoSave,app.OutputFolder,app.BrowseButton};
            for idx = 1:numel(metadataControls)
                metadataControls{idx}.Enable = app.enabled(~recording && ~app.Busy);
            end
            completed = ~isempty(app.Recordings) && ~recording && ~app.Busy;
            app.SaveButton.Enable = app.enabled(completed);
            app.RecordingSelector.Enable = app.enabled(completed);
        end

        function closeApp(app)
            if app.Busy, return; end
            app.stopAcquisition();
            unsaved = find(cellfun(@isempty,app.SavedFiles));
            if ~isempty(unsaved)
                choice = uiconfirm(app.Figure,'There are unsaved recordings.', ...
                    'Close application','Options',{'Save all','Discard','Cancel'}, ...
                    'DefaultOption',1,'CancelOption',3);
                if strcmp(choice,'Cancel'), return; end
                if strcmp(choice,'Save all')
                    try
                        for idx = unsaved, app.saveRecording(idx,''); end
                    catch exception
                        app.sessionError(exception); return;
                    end
                end
            end
            delete(app);
        end

        function text = enabled(~,condition)
            if condition, text = 'on'; else, text = 'off'; end
        end

        function removeTemporary(~,file)
            if isfile(file), delete(file); end
        end

        function createSettings(app,parent)
            tabs = uitabgroup(parent);
            app.addSettingsTab(tabs,'Acquisition',{
                'numberOfGrids','Number of grids',2,'number';
                'forcePort','Arduino port','COM3','text';
                'activeInputs','Physical inputs','1:2','text';
                'calibChannels','Calibration channels','1:128','text';
                'emgChannels','Stream EMG channels','1:64 71:134','text';
                'emgPreviewChannels','Preview EMG channels','1:8:128','channels';
                'forceInputChannelCounts','Channels per input','70 70 0 0 0 0 0 0 0 0','text';
                'blockDurationSec','EMG processing window (s)',0.128,'number';
                'visibleWindowSec','EMG time window (s)',10,'number';
                'forceDisplayTimeSec','Force time window (s)',10,'number';
                'onlineDurationSec','Session duration (s)','Inf','text';
                'forceFs','Force sampling rate (Hz)',50,'number';
                'forcePlotRateHz','Live plot refresh rate (Hz)',10,'number';
                'forceTargetMVC','Force target (% MVC)',30,'number';
                'printEveryNWindows','Print summary window',10,'number';
                'recordEMG','Retain EMG',true,'check';
                'showForceTarget','Show MVC target line',true,'check'});
            app.addSettingsTab(tabs,'Force calibration',{
                'forcePromptCalibration','Prompt if file missing',true,'check';
                'forceDefaultCalibrationFactors','Default factors','10 10 10','text';
                'forceDefaultZeroValues','Default zero values','0 0 0','text';
                'forceDefaultReverseStates','Default reverse (0/1)','0 0 0','text';
                'extensionPositive','Extension is positive',false,'check'});
            app.Inputs.numberOfGrids.ValueChangedFcn = @(~,~) app.updateGridMapping();
            app.Inputs.activeInputs.Tooltip = 'Physical inputs in calibration grid order.';
            app.Inputs.onlineDurationSec.Tooltip = 'Inf means stop manually.';
            app.Inputs.emgChannels.Tooltip = 'Stream rows paired with calibration channels; skip six auxiliary rows per probe.';
            app.Inputs.forceTargetMVC.Tooltip = ...
                'Horizontal force reference from 0 to 100% MVC; set before acquisition.';
            app.Inputs.emgPreviewChannels.Tooltip = ...
                'Calibration electrode rows to display. Use Choose to select by grid/channel. Recording and decoding still use all configured electrodes.';
        end

        function addSettingsTab(app,tabs,title,fields)
            tab = uitab(tabs,'Title',title,'BackgroundColor',[0.96 0.955 0.94]);
            grid = uigridlayout(tab,[size(fields,1) 2], ...
                'ColumnWidth',{'1x',155}, ...
                'RowHeight',repmat({34},1,size(fields,1)), ...
                'Padding',[8 8 8 8],'RowSpacing',6, ...
                'BackgroundColor',[0.96 0.955 0.94],'Scrollable','on');
            for row = 1:size(fields,1)
                uilabel(grid,'Text',fields{row,2},'FontColor',[0.12 0.12 0.12], ...
                    'WordWrap','on');
                switch fields{row,4}
                    case 'number'
                        control = uieditfield(grid,'numeric','Value',fields{row,3});
                    case 'text'
                        control = uieditfield(grid,'text','Value',fields{row,3});
                    case 'check'
                        control = uicheckbox(grid,'Text','','Value',fields{row,3});
                    case 'mu'
                        control = uidropdown(grid,'Items', ...
                            {'G1 MU1','G1 MU2','G1 MU3','G2 MU1','G2 MU2','G2 MU3'}, ...
                            'ItemsData',1:6,'Value',fields{row,3});
                    case 'channels'
                        selector = uigridlayout(grid,[1 2], ...
                            'ColumnWidth',{'1x',65},'Padding',[0 0 0 0], ...
                            'ColumnSpacing',4,'BackgroundColor',[0.96 0.955 0.94]);
                        control = uieditfield(selector,'Value',fields{row,3});
                        app.ChannelButton = uibutton(selector,'Text','Choose', ...
                            'Tag','chooseEMGChannels', ...
                            'ButtonPushedFcn',@(~,~) app.chooseEmgChannels());
                end
                if ~strcmp(fields{row,4},'check')
                    control.BackgroundColor = [0.98 0.975 0.96];
                    control.FontColor = [0.12 0.12 0.12];
                end
                app.Inputs.(fields{row,1}) = control;
                control.Tag = fields{row,1};
            end
        end

        function updateGridMapping(app)
            n = app.Inputs.numberOfGrids.Value;
            if ~ismember(n,1:10), return; end
            app.Inputs.activeInputs.Value = sprintf('1:%d',n);
            app.Inputs.calibChannels.Value = sprintf('1:%d',64*n);
            segments = arrayfun(@(g) sprintf('%d:%d',70*g+1,70*g+64), ...
                0:n-1,'UniformOutput',false);
            app.Inputs.emgChannels.Value = strjoin(segments,' ');
            app.Inputs.forceInputChannelCounts.Value = ...
                strtrim(sprintf('%d ',[repmat(70,1,n) zeros(1,10-n)]));
            app.Inputs.emgPreviewChannels.Value = sprintf('1:8:%d',64*n);
            app.refreshMuChoices();
        end

        function chooseEmgChannels(app)
            try
                n = app.Inputs.numberOfGrids.Value;
                validateattributes(n,{'numeric'},{'scalar','integer','>=',1,'<=',10});
                labels = arrayfun(@(row) sprintf('Grid %d / Channel %d (row %d)', ...
                    floor((row-1)/64)+1,mod(row-1,64)+1,row), ...
                    1:64*n,'UniformOutput',false);
                selected = app.parseNumbers(app.Inputs.emgPreviewChannels.Value);
                validateattributes(selected,{'numeric'}, ...
                    {'vector','nonempty','integer','positive','<=',64*n});
                [chosen,accepted] = listdlg('ListString',labels, ...
                    'SelectionMode','multiple','InitialValue',selected, ...
                    'PromptString','Select electrodes for the live EMG preview:', ...
                    'Name','EMG preview channels','ListSize',[340 420]);
                if accepted && ~isempty(chosen)
                    app.Inputs.emgPreviewChannels.Value = strtrim(sprintf('%d ',chosen));
                end
            catch exception
                uialert(app.Figure,exception.message,'EMG channel selection');
            end
        end

        function refreshMuChoices(app)
            if isempty(app.Mode), return; end
            n = app.Inputs.numberOfGrids.Value;
            if ~ismember(n,1:10), return; end
            counts = repmat(3,1,n);
            if ~strcmp(app.Mode.Value,'Simulation') && ...
                    ~isempty(fieldnames(app.CalibrationData))
                counts = cellfun(@(p) size(p,1),app.CalibrationData.Pulsetrain);
            end
            nMU = sum(counts);
            for name = {'quadrantXMU','quadrantYMU'}
                app.QuadrantSettings.(name{1}) = ...
                    min(max(1,app.QuadrantSettings.(name{1})),max(1,nMU));
            end
            app.QuadrantSettings.showQuadrant = nMU >= 2;
            if nMU >= 2 && app.QuadrantSettings.quadrantXMU == app.QuadrantSettings.quadrantYMU
                app.QuadrantSettings.quadrantYMU = mod(app.QuadrantSettings.quadrantXMU,nMU)+1;
            end
        end

        function values = parseNumbers(~,text)
            % Parse numeric lists/ranges without evaluating MATLAB expressions.
            text = strtrim(text);
            if strcmp(text,'[]'), values = []; return; end
            text = regexprep(text,'^\[|\]$','');
            tokens = regexp(text,'[\s,;]+','split');
            values = [];
            for idx = 1:numel(tokens)
                parts = strsplit(tokens{idx},':');
                numbers = cellfun(@str2double,parts);
                assert(~any(isnan(numbers)) && numel(parts) <= 3, ...
                    'Enter numbers or ranges such as 1:64 71:134.');
                if isscalar(numbers)
                    next = numbers;
                else
                    assert(all(isfinite(numbers)), 'Ranges must have finite endpoints.');
                    step = 1;
                    if numel(numbers) == 3, step = numbers(2); end
                    assert(step ~= 0 && abs((numbers(end)-numbers(1))/step) <= 10000, ...
                        'Range must have a nonzero step and at most 10001 entries.');
                    next = numbers(1):step:numbers(end);
                end
                values = [values next]; %#ok<AGROW>
            end
        end

        function importDecomposition(app,file)
            if nargin < 2
                [name,folder] = uigetfile('*.mat', ...
                    'Load MU filter from edited decomposition result', ...
                    fileparts(mfilename('fullpath')));
                if isequal(name,0), return; end
                file = fullfile(folder,name);
            end
            try
                session = load(file,'signal','edition','parameters');
                assert(all(isfield(session,{'signal','edition','parameters'})), ...
                    'Select an edited result containing signal, edition and parameters.');
                signal = session.signal;
                edition = session.edition;
                assert(isstruct(signal) && isscalar(signal) && ...
                    all(isfield(signal,{'data','fsamp','EMGmask'})), ...
                    'The signal structure must contain data, fsamp and EMGmask.');
                assert(isstruct(session.parameters) && isscalar(session.parameters), ...
                    'parameters must be a scalar structure.');
                assert(isstruct(edition) && isscalar(edition) && ...
                    all(isfield(edition,{'Pulsetrain','Dischargetimes'})), ...
                    'edition must contain Pulsetrain and Dischargetimes.');
                validateattributes(signal.fsamp,{'numeric'}, ...
                    {'scalar','positive','finite'});
                validateattributes(signal.data,{'numeric'},{'2d','nonempty'});
                assert(iscell(signal.EMGmask) && ~isempty(signal.EMGmask), ...
                    'EMGmask must contain one mask per grid.');
                nGrids = numel(signal.EMGmask);
                assert(sum(cellfun(@numel,signal.EMGmask)) == size(signal.data,1), ...
                    'Grid masks do not match the calibration EMG channels.');
                assert(iscell(edition.Pulsetrain) && ...
                    numel(edition.Pulsetrain) == nGrids && ...
                    iscell(edition.Dischargetimes) && ...
                    size(edition.Dischargetimes,1) == nGrids, ...
                    'Edited results must provide pulse trains and discharge cells for every grid.');
                counts = cellfun(@(pulse) size(pulse,1),edition.Pulsetrain);
                assert(all(cellfun(@(pulse) isnumeric(pulse) && ...
                    size(pulse,2) == size(signal.data,2),edition.Pulsetrain)) && ...
                    size(edition.Dischargetimes,2) >= max(counts), ...
                    'Edited pulse-train lengths or discharge-cell counts are inconsistent.');
                signal.Pulsetrain = edition.Pulsetrain;
                signal.Dischargetimes = edition.Dischargetimes;
                signal.onlineMUReferenceRates = get_mu_reference_rates(signal,edition);
                signal.onlineMUOriginalIDs = cell(1,nGrids);
                for g = 1:nGrids
                    signal.onlineMUOriginalIDs{g} = 1:counts(g);
                    name = sprintf('grid%d',g);
                    if isfield(edition,'edit_stats') && isfield(edition.edit_stats,name) && ...
                            isfield(edition.edit_stats.(name),'quality_filter_kept_mu')
                        signal.onlineMUOriginalIDs{g} = ...
                            edition.edit_stats.(name).quality_filter_kept_mu;
                    end
                end
                % Commit only after validation; failed imports preserve prior data.
                app.CalibrationData = signal;
                app.Parameters = session.parameters;
                app.DecompositionFile = file;
                [~,base,extension] = fileparts(file);
                app.DecompositionLabel.Text = [base extension];
                app.DecompositionLabel.Tooltip = file;
                gridDetails = sprintf('Grid %d: %d MUs\n',[1:nGrids; counts(:).']);
                app.DecompositionSummary.Text = sprintf( ...
                    'MU filter is loaded successfully.\nGrids: %d\n%sSampling rate: %g Hz', ...
                    nGrids,gridDetails,signal.fsamp);
                app.DecompositionSummary.Parent.RowHeight{4} = 18*(nGrids+3)+8;
                app.Inputs.numberOfGrids.Value = nGrids;
                app.updateGridMapping();
            catch exception
                uialert(app.Figure,exception.message,'Decomposition import failed');
            end
        end

        function importForceCalibration(app,file)
            if nargin < 2
                [name,folder] = uigetfile('*.mat','Load Force Calibration file', ...
                    fileparts(mfilename('fullpath')));
                if isequal(name,0), return; end
                file = fullfile(folder,name);
            end
            try
                calibration = load(file,'calibrationFactors','zeroValues','reverseStates');
                assert(all(isfield(calibration, ...
                    {'calibrationFactors','zeroValues','reverseStates'})), ...
                    'File must contain calibrationFactors, zeroValues and reverseStates.');
                validateattributes(calibration.calibrationFactors,{'numeric'}, ...
                    {'vector','numel',3,'finite','nonzero'});
                validateattributes(calibration.zeroValues,{'numeric'}, ...
                    {'vector','numel',3,'finite'});
                validateattributes(calibration.reverseStates,{'numeric','logical'}, ...
                    {'vector','numel',3,'binary'});
                app.ForceCalibration = calibration;
                app.ForceCalibrationFile = file;
                [~,base,extension] = fileparts(file);
                app.ForceLabel.Text = [base extension];
                app.ForceLabel.Tooltip = file;
                app.ForceSummary.Text = 'Force Calibration file is loaded successfully.';
            catch exception
                uialert(app.Figure,exception.message,'Force calibration import failed');
            end
        end
    end
end
