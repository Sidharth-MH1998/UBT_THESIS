function test_quadrant_window()
%TEST_QUADRANT_WINDOW Settings live in the popup and persist into recorded cfg.
app = OnlineDecompositionApp();
cleanup = onCleanup(@() delete(app));
app.Figure.Visible = 'off';
autoSave = findall(app.Figure,'Tag','autoSave');
autoSave.Value = false;
assert(isempty(findall(app.Figure,'Tag','quadrantXMU')));
click(app.Figure,'Start acquisition');
pause(0.2); drawnow;
click(app.Figure,'Open quadrant');
popup = findall(groot,'Tag','OnlineAppQuadrantWindow');
x = findall(popup,'Tag','quadrantXMU');
y = findall(popup,'Tag','quadrantYMU');
smoothing = findall(popup,'Tag','quadrantSmoothingWindows');
window = findall(popup,'Tag','quadrantRateWindowSec');
history = findall(popup,'Tag','quadrantHistorySec');
axisMax = findall(popup,'Tag','quadrantAxisMax');
x.Value = 1;
y.Value = 4;
smoothing.Value = 6;
window.Value = 0.75;
history.Value = 5;
axisMax.Value = 45;
click(popup,'Apply settings');
cfg = app.getConfig();
assert(cfg.quadrantXMU == 1 && cfg.quadrantYMU == 4);
assert(cfg.quadrantSmoothingWindows == 6 && cfg.quadrantAxisMax == 45);
raster = findall(popup,'Tag','quadrantSelectedMURaster');
assert(isscalar(raster));
assert(isequal(cellstr(raster.YTickLabel),{'X: G1 MU1';'Y: G2 MU1'}));
assert(numel(findall(raster,'Type','line')) == 2);
click(app.Figure,'Start recording');
pause(0.3); drawnow;
assert(strcmp(findall(popup,'Tag','applyQuadrantSettings').Enable,'off'));
close(popup);
click(app.Figure,'Open quadrant');
popup = findall(groot,'Tag','OnlineAppQuadrantWindow');
assert(strcmp(findall(popup,'Tag','quadrantXMU').Enable,'off'));
assert(findall(popup,'Tag','quadrantYMU').Value == 4);
raster = findall(popup,'Tag','quadrantSelectedMURaster');
assert(isequal(cellstr(raster.YTickLabel),{'X: G1 MU1';'Y: G2 MU1'}));
assert(strcmp(findall(app.Figure,'Text','Stop recording').Enable,'on'));
click(app.Figure,'Stop recording');
assert(app.LastResults.cfg.quadrantYMU == 4);
assert(app.LastResults.cfg.quadrantSmoothingWindows == 6);
assert(strcmp(findall(popup,'Tag','applyQuadrantSettings').Enable,'on'));
click(app.Figure,'Stop acquisition');
root = fileparts(fileparts(mfilename('fullpath')));
exportapp(popup,fullfile(root,'tmp','online_app_validation','quadrant_settings_preview.png'));
disp('Quadrant popup settings, persistence and recording-lock checks passed.');
end

function click(parent,label)
button = findall(parent,'Text',label);
assert(isscalar(button) && strcmp(button.Enable,'on'),'Unavailable button: %s',label);
callback = button.ButtonPushedFcn;
callback(button,[]);
drawnow;
end
