function test_force_plot_sample_count()
%TEST_FORCE_PLOT_SAMPLE_COUNT Only new force samples trigger force line updates.
addpath(fullfile(fileparts(fileparts(mfilename('fullpath'))),'OnlineDecomposeSrc'));
app = OnlineDecompositionApp();
appCleanup = onCleanup(@() delete(app));
app.Figure.Visible = 'off';
cfg = app.getConfig();
cfg.fs = 2000;
cfg.forceFs = 50;
cfg.forcePlotRateHz = 10;
cfg.quadrantReferenceRates = [12 14];
labels = {'G1 MU1','G1 MU2'};
fig = uifigure('Visible','off');
figCleanup = onCleanup(@() delete(fig));
dashboard = OnlineAppDashboard(fig);
dashboardCleanup = onCleanup(@() delete(dashboard));
dashboard.initialize(cfg,labels);
task = ExperimentalTaskWindow(cfg,labels,@(~) [],@() []);
taskCleanup = onCleanup(@() delete(task));
mainLine = findall(fig,'Type','line','DisplayName','Thumb');
taskLine = findall(task.FeedbackFigure,'Type','line','DisplayName','Thumb');
assert(isscalar(mainLine) && isscalar(taskLine));
% Long wall/sample-time gaps do not bypass the five-sample requirement.
for k = 1:4
    send(k*0.2,k);
    assert(all(isnan(mainLine.YData)) && all(isnan(taskLine.YData)));
end
send(1,5);
assert(numel(mainLine.YData)==5 && numel(taskLine.YData)==5);
% No new force samples must not redraw even if time advances.
send(1.1,[]);
assert(numel(mainLine.YData)==5 && numel(taskLine.YData)==5);
% A buffered batch is drawn once in full and preserves the residual count.
send(1.34,6:17);
assert(numel(mainLine.YData)==17 && numel(taskLine.YData)==17);
assert(isequal(mainLine.YData(:),(1:17)'));
assert(isequal(taskLine.YData(:),(1:17)'));
send(1.38,18:19);
assert(numel(mainLine.YData)==17 && numel(taskLine.YData)==17);
send(1.4,20);
assert(numel(mainLine.YData)==20 && numel(taskLine.YData)==20);
disp('Main and task force sample-count plotting checks passed.');

    function send(time,values)
        values = values(:);
        count = numel(values);
        force = struct('data',repmat(values,1,3), ...
            'sessionTime',time-0.02*(count-1:-1:0)', ...
            'arduinoTime',zeros(count,1));
        frame = struct('time',time,'sampleCursor',0,'pulse',zeros(2,0), ...
            'spikes',false(0,2),'emg',zeros(128,0),'force',force);
        dashboard.update(frame);
        task.updateFrame(frame);
    end
end
