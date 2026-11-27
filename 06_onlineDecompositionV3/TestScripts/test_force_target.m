function test_force_target()
%TEST_FORCE_TARGET Verify the target overlay and saved trial configuration.
addpath(fullfile(fileparts(fileparts(mfilename('fullpath'))),'OnlineDecomposeSrc'));
app = OnlineDecompositionApp();
cleanup = onCleanup(@() delete(app));
app.Figure.Visible = 'off';
autoSave = findall(app.Figure,'Tag','autoSave');
autoSave.Value = false;
target = findall(app.Figure,'Tag','forceTargetMVC');
toggle = findall(app.Figure,'Tag','showForceTarget');
target.Value = 30;
toggle.Value = true;
click(app,'Start acquisition');
pause(0.3); drawnow;
line = findall(app.Figure,'Tag','forceMVCTarget');
assert(isscalar(line) && line.Value == 30 && strcmp(line.Visible,'on'));
assert(contains(line.Label,'30% MVC'));
forceAxes = findall(app.Figure,'Tag','liveForceAxes');
emgAxes = findall(app.Figure,'Tag','liveEMGAxes');
assert(isequal(forceAxes.YLim,[-10 80]));
assert(forceAxes.XLim(1) == emgAxes.XLim(1));
assert(abs(forceAxes.XLim(2)-emgAxes.XLim(2)-5) < 1e-10);
click(app,'Start recording');
pause(0.3); drawnow;
click(app,'Stop recording');
assert(app.LastResults.cfg.forceTargetMVC == 30 && app.LastResults.cfg.showForceTarget);
click(app,'Stop acquisition');
target.Value = 60;
toggle.Value = false;
cfg = app.getConfig();
assert(cfg.forceTargetMVC == 60 && ~cfg.showForceTarget);
click(app,'Start acquisition');
pause(0.2); drawnow;
line = findall(app.Figure,'Tag','forceMVCTarget');
assert(isscalar(line) && line.Value == 60 && strcmp(line.Visible,'off'));
click(app,'Stop acquisition');
app.Figure.Position = [20 20 1920 1000];
drawnow;
assert(emgAxes.Position(4) > forceAxes.Position(4));
folder = fullfile(fileparts(fileparts(fileparts(mfilename('fullpath')))),'tmp','online_app_validation');
if ~isfolder(folder), mkdir(folder); end
exportapp(app.Figure,fullfile(folder,'live_feedback_scaling_preview.png'));
disp('MVC force target overlay and recording settings checks passed.');
end

function click(app,label)
button = findall(app.Figure,'Text',label);
assert(isscalar(button) && strcmp(button.Enable,'on'),'Unavailable button: %s',label);
callback = button.ButtonPushedFcn;
callback(button,[]);
drawnow;
end
