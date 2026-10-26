function test_force_target()
%TEST_FORCE_TARGET Verify the target overlay and saved trial configuration.
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
disp('MVC force target overlay and recording settings checks passed.');
end

function click(app,label)
button = findall(app.Figure,'Text',label);
assert(isscalar(button) && strcmp(button.Enable,'on'),'Unavailable button: %s',label);
callback = button.ButtonPushedFcn;
callback(button,[]);
drawnow;
end
