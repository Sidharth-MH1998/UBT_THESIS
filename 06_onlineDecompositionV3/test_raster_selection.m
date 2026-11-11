function test_raster_selection()
%TEST_RASTER_SELECTION Verify 29+5 MU scrolling, mapping and display-only selection.
app = OnlineDecompositionApp();
appCleanup = onCleanup(@() delete(app));
app.Figure.Visible = 'off';
cfg = app.getConfig();
cfg.fs = 2000;
labels = [arrayfun(@(mu) sprintf('G1 MU%d',mu),1:29,'UniformOutput',false), ...
    arrayfun(@(mu) sprintf('G2 MU%d',mu),1:5,'UniformOutput',false)];
fig = uifigure('Visible','off');
figureCleanup = onCleanup(@() delete(fig));
dashboard = OnlineAppDashboard(fig);
dashboardCleanup = onCleanup(@() delete(dashboard));
dashboard.initialize(cfg,labels);
n = 256;
spikes = false(n,34);
for mu = 1:34, spikes(2*mu+1,mu) = true; end
frame = struct('time',n/cfg.fs,'sampleCursor',n,'pulse',zeros(34,n), ...
    'spikes',spikes,'emg',zeros(128,n), ...
    'force',struct('data',zeros(0,3),'sessionTime',zeros(0,1)));
dashboard.update(frame);
button = findall(fig,'Tag','openRaster');
button.ButtonPushedFcn(button,[]);
popup = findall(groot,'Tag','OnlineAppRasterWindow');
viewport = findall(popup,'Tag','rasterScrollViewport');
ax = findall(popup,'Tag','rasterMUAxes');
selector = findall(popup,'Tag','rasterMUSelector');
assert(strcmp(viewport.Scrollable,'on'));
assert(viewport.RowHeight{1} >= 28*34+90);
assert(numel(findall(ax,'Type','line')) == 34);
assert(isequal(cellstr(ax.YTickLabel),labels(:)));
folder = fullfile(fileparts(fileparts(mfilename('fullpath'))),'tmp','online_app_validation');
if ~isfolder(folder), mkdir(folder); end
exportapp(popup,fullfile(folder,'raster_scroll_preview.png'));
selected = [1 29 30 34];
selector.Value = selected;
selector.ValueChangedFcn(selector,[]);
assert(isequal(cellstr(ax.YTickLabel),labels(selected).'));
assert(viewport.RowHeight{1} < 28*34+90);
traces = findall(ax,'Type','line');
assert(numel(traces) == 4);
for trace = traces'
    row = trace.YData(1);
    assert(abs(trace.XData(1)-2*selected(row)/cfg.fs) < 1e-12);
end
% New frames still contain every MU; selected rows update from their own spikes.
frame.time = 2*n/cfg.fs;
frame.sampleCursor = 2*n;
dashboard.update(frame);
assert(size(frame.spikes,2) == 34);
assert(numel(findall(ax,'Type','line')) == 4);
close(popup);
button.ButtonPushedFcn(button,[]);
popup = findall(groot,'Tag','OnlineAppRasterWindow');
selector = findall(popup,'Tag','rasterMUSelector');
assert(isequal(selector.Value,selected));
allButton = findall(popup,'Tag','rasterSelectAll');
allButton.ButtonPushedFcn(allButton,[]);
assert(isequal(selector.Value,1:34));
assert(numel(findall(findall(popup,'Tag','rasterMUAxes'),'Type','line')) == 34);
disp('34-MU scrolling, selected-MU mapping, live updates and selection persistence passed.');
end
