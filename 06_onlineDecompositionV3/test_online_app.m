function test_online_app()
%TEST_ONLINE_APP Exercise preview, recording boundaries, saving and embedded UI.
% Uses simulation only. Artifacts are written under tmp/online_app_validation.
root = fileparts(fileparts(mfilename('fullpath')));
folder = fullfile(root,'tmp','online_app_validation');
if ~isfolder(folder), mkdir(folder); end
app = OnlineDecompositionApp();
cleanup = onCleanup(@() delete(app));
app.Figure.Visible = 'off';
cfg = app.getConfig();
cfg.printEveryNWindows = 0;
cfg.forceMaxDurationSec = 30;
session = OnlineAcquisitionSession(cfg,struct(),struct());
sessionCleanup = onCleanup(@() delete(session));
session.start(false);
assert(session.Running && ~session.Recording && size(session.MuMap,1) == 6);
session.advanceSimulation();
session.advanceSimulation();
startSample = session.SampleCursor;
metadata = struct('participant','TEST','session',1,'trial',1);
session.startRecording(metadata);
for window = 1:5, session.advanceSimulation(); end
first = session.stopRecording();
assert(~session.Recording && session.Running);
assert(first.startSample == startSample);
assert(size(first.online.Pulsetrain,2) == 5*cfg.blockDurationSec*2000);
assert(numel(first.online.gridResults) == 2 && first.simulation);
assert(all(first.online.force.Time >= 0));
for g = 1:2
    result = first.online.gridResults{g};
    assert(size(result.EMG,1) == 64 && size(result.Pulsetrain,1) == 3);
    assert(isequal(result.Pulsetrain,first.online.Pulsetrain(result.globalMUIndices,:)));
    for mu = 1:3
        assert(isequal(result.Dischargetimes{mu},find(result.Distime(:,mu))));
    end
end
session.advanceSimulation(); % Preview gap must not enter the next recording.
session.zeroForce();
metadata.trial = 2;
session.startRecording(metadata);
session.advanceSimulation();
second = session.stopRecording();
assert(size(second.online.Pulsetrain,2) == 256);
assert(second.startSample > first.startSample+size(first.online.Pulsetrain,2));
assert(second.online.Time(1) == 0 && second.metadata.trial == 2);
assert(max(abs(second.online.force.data(:))) < 15,'Force zero did not take effect.');
session.stop();
assert(~session.Running);

% Force capacity ends recording, preserving acquisition and the final EMG window.
cfg.forceMaxDurationSec = 0.1;
limited = OnlineAcquisitionSession(cfg,struct(),struct());
limitedCleanup = onCleanup(@() delete(limited));
limited.start(false);
limited.startRecording(metadata);
limited.advanceSimulation();
assert(limited.Running && ~limited.Recording);
assert(size(limited.LastRecording.online.force.data,1) == 5);
assert(size(limited.LastRecording.online.Pulsetrain,2) == 256);
limited.stop();

% Exercise the actual buttons, embedded plots and automatic MAT-file save.
output = findall(app.Figure,'Tag','outputFolder');
output.Value = folder;
preview = findall(app.Figure,'Tag','emgPreviewChannels');
preview.Value = '1 66 128';
click(app,'Start acquisition');
pause(0.3); drawnow;
chooser = findall(app.Figure,'Tag','chooseEMGChannels');
assert(isscalar(chooser) && strcmp(chooser.Enable,'off'));
assert(isempty(findall(groot,'Tag','OnlineAppRasterWindow')));
assert(isempty(findall(groot,'Tag','OnlineAppRateWindow')));
assert(isempty(findall(groot,'Tag','OnlineAppQuadrantWindow')));
click(app,'Start recording');
pause(0.6); drawnow;
click(app,'Open firing rates');
click(app,'Open quadrant');
click(app,'Open raster');
emgAxes = findall(app.Figure,'Tag','liveEMGAxes');
assert(isequal(cellstr(emgAxes.YTickLabel),{'G1 Ch1';'G2 Ch2';'G2 Ch64'}));
rateWindow = findall(groot,'Tag','OnlineAppRateWindow');
quadrantWindow = findall(groot,'Tag','OnlineAppQuadrantWindow');
rasterWindow = findall(groot,'Tag','OnlineAppRasterWindow');
assert(isscalar(rasterWindow));
assert(isscalar(rateWindow) && isscalar(quadrantWindow));
click(app,'Open firing rates');
click(app,'Open quadrant');
click(app,'Open raster');
assert(isscalar(findall(groot,'Tag','OnlineAppRasterWindow')));
assert(isscalar(findall(groot,'Tag','OnlineAppRateWindow')));
assert(isscalar(findall(groot,'Tag','OnlineAppQuadrantWindow')));
close(rateWindow);
close(quadrantWindow);
close(rasterWindow);
assert(strcmp(findall(app.Figure,'Text','Stop recording').Enable,'on'), ...
    'Recording stopped unexpectedly: %s', ...
    findall(app.Figure,'Tag','acquisitionStatus').Text);
click(app,'Open firing rates');
click(app,'Open quadrant');
click(app,'Open raster');
click(app,'Stop recording');
assert(isscalar(app.Recordings) && isfile(app.SavedFiles{1}));
loaded = load(app.SavedFiles{1},'data_out');
assert(loaded.data_out.simulation && loaded.data_out.elapsedSec > 0);
assert(size(loaded.data_out.online.EMG,1) == 128);
assert(isequal(loaded.data_out.cfg.emgPreviewChannels,[1 66 128]));
click(app,'Start recording');
pause(0.3); drawnow;
click(app,'Stop acquisition');
assert(numel(app.Recordings) == 2 && isfile(app.SavedFiles{2}));
assert(strcmp(findall(app.Figure,'Text','Start acquisition').Enable,'on'));
exportapp(findall(groot,'Tag','OnlineAppRateWindow'),fullfile(folder,'firing_rates_preview.png'));
exportapp(findall(groot,'Tag','OnlineAppQuadrantWindow'),fullfile(folder,'quadrant_preview.png'));
exportapp(app.Figure,fullfile(folder,'app_preview.png'));
fixture = fullfile(folder,'edited_fixture.mat');
if isfile(fixture)
    app.loadDecomposition(fixture);
    assert(numel(app.CalibrationData.Pulsetrain) == 3);
    mode = findall(app.Figure,'Tag','acquisitionMode');
    mode.Value = 'Replay calibration';
    callback = mode.ValueChangedFcn;
    callback(mode,[]);
    imported = app.getConfig();
    assert(imported.numberOfGrids == 3);
    assert(isempty(findall(app.Figure,'Tag','quadrantXMU')));
    assert(imported.quadrantXMU <= 3 && imported.quadrantYMU <= 3);
end
% Import real calibration field shapes, including signed factors and reversals.
calibrationFactors = [10;-20;30];
zeroValues = [1;2;3];
reverseStates = [true;false;true];
calibrationFile = fullfile(folder,'force_fixture.mat');
save(calibrationFile,'calibrationFactors','zeroValues','reverseStates');
app.loadForceCalibration(calibrationFile);
imported = app.getConfig();
assert(isequal(imported.forceCalibration.calibrationFactors,[10 -20 30]));
assert(isequal(imported.forceCalibration.zeroValues,[1 2 3]));
assert(isequal(imported.forceCalibration.reverseStates,[true false true]));
disp('Online app simulation, recording and saving checks passed.');
end

function click(app,label)
button = findall(app.Figure,'Text',label);
assert(isscalar(button) && strcmp(button.Enable,'on'), ...
    'Button is not available: %s',label);
callback = button.ButtonPushedFcn;
callback(button,[]);
drawnow;
end
