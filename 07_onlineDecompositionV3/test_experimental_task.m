function test_experimental_task()
% Exercise scoring independently, then open, run and save a simulated UI block.
s = struct('mu',[1 2],'referencePPS',[100 100],'gain',[1 1], ...
    'targetRadius',0.10,'angleInnerRadius',0.40,'targetHold',0.2,'angleHold',0.2, ...
    'timeout',0.9,'restTime',0.1,'restRadius',0.1,'rateWindow',0.1, ...
    'repetitions',1,'smoothing',1,'seed',24,'randomize',false);
task = MotorUnitTargetTask(s,1000);
t = 0;
step([0 0]); step([0 0]);
assert(strcmp(task.Phase,'attempt'));
step([1 0]); step([0 0]); % An interrupted hold must start again.
step([1 0]); step([1 0]);
assert(isempty(task.Trials));
step([1 0]);
assert(task.Trials(1).targetHit && task.Trials(1).angleHit);
assert(abs(task.Trials(1).timeToTargetSec-0.5)<1e-9);
step([0 0]); step([0 0]);
for k = 1:3, step([1 0]); end
for k = 1:6, step([0.6 0.6]); end
assert(strcmp(task.Trials(2).outcome,'timeout') && task.Trials(2).angleHit);
assert(~task.Trials(2).targetHit && isfinite(task.Trials(2).nearestDistance));
assert(task.Trials(2).targetHitCounts(1)==1);
step([0 0]); step([0 0]);
task.abort('stopped');
assert(strcmp(task.Trials(3).outcome,'aborted') && strcmp(task.Completion,'stopped'));
s.randomize = true;
s.repetitions = 4;
a = MotorUnitTargetTask(s,1000);
b = MotorUnitTargetTask(s,1000);
assert(isequal(a.Schedule,b.Schedule) && isequal(sort(a.Schedule),repelem(1:3,4)));

app = OnlineDecompositionApp();
cleanup = onCleanup(@() delete(app));
app.Figure.Visible = 'off';
folder = tempname;
mkdir(folder);
outputFolder = findall(app.Figure,'Tag','outputFolder');
outputFolder.Value = folder;
click(findall(app.Figure,'Tag','openExperimentalTask'));
window = findall(groot,'Tag','onlineExperimentalTask');
assert(isscalar(window));
feedback = findall(groot,'Tag','onlineExperimentalFeedback');
assert(isscalar(feedback));
assert(isempty(findall(feedback,'Tag','startExperimentalTask')));
assert(isempty(findall(window,'Tag','experimentalCursor')));
click(findall(app.Figure,'Tag','openExperimentalTask'));
assert(isscalar(findall(groot,'Tag','onlineExperimentalFeedback')));
start = findall(window,'Tag','startExperimentalTask');
assert(strcmp(start.Enable,'off'));
setValue('targetHold',0.256);
setValue('angleHold',0.256);
setValue('restTime',0.256);
setValue('timeout',3);
setValue('rateWindow',0.128);
setValue('smoothing',1);
setValue('repetitions',1);
setValue('randomize',false);
setValue('xRef',15.625);
setValue('yRef',15.625);
setValue('cursorHistory',2.5);
click(findall(window,'Tag','applyExperimentalTaskSettings'));
click(findall(app.Figure,'Text','Start acquisition'));
assert(strcmp(start.Enable,'on'));
cursor = findall(feedback,'Tag','experimentalCursor');
clock = tic;
while ~isfinite(cursor.XData) && toc(clock)<10
    pause(0.05);
end
assert(isfinite(cursor.XData) && isfinite(cursor.YData) && isempty(app.Recordings));
click(start);
assert(strcmp(start.Enable,'off'));
clock = tic;
while isempty(app.Recordings) && toc(clock)<35
    pause(0.05);
end
assert(~isempty(app.Recordings),'Simulated block did not finish.');
result = app.LastResults;
assert(strcmp(result.task.completion,'complete'));
assert(isequal([result.task.trials.target],[1 2 3]));
assert(all([result.task.trials.targetHit]));
assert(isequal(result.task.settings.referencePPS,[15.625 15.625]));
assert(result.task.settings.cursorHistory==2.5);
assert(result.task.settings.simulatedGuidance && result.simulation);
assert(numel(result.task.timeSec)==result.nWin);
assert(isfile(app.SavedFiles{1}));
saved = load(app.SavedFiles{1});
assert(isequal(fieldnames(saved),{'task_data'}));
assert(isequaln(saved.task_data.task,result.task));
assert(~isfield(saved.task_data,'online'));
assert(isequaln(saved.task_data.fulltask_data,result.fulltask_data));
assert(~isempty(saved.task_data.fulltask_data.Pulsetrain));
click(findall(app.Figure,'Text','Stop acquisition'));
root = fileparts(fileparts(mfilename('fullpath')));
exportapp(window,fullfile(root,'tmp','experimental_task_preview.png'));
feedback.Position = [20 20 1500 900];
drawnow;
exportapp(feedback,fullfile(root,'tmp','experimental_feedback_preview.png'));
close(feedback);
assert(~isgraphics(window) && isempty(findall(groot,'Tag','onlineExperimentalFeedback')));

% Check the default-length simulation with real session buffers, without a timer.
cfg = app.getConfig();
cfg.printEveryNWindows = 0;
session = OnlineAcquisitionSession(cfg,struct(),struct());
sessionCleanup = onCleanup(@() delete(session));
session.start(false);
defaults = result.task.settings;
defaults.referencePPS = session.Config.quadrantReferenceRates(defaults.mu);
defaults.targetHold = 0.875;
defaults.angleHold = 0.875;
defaults.restTime = 2;
defaults.timeout = 20;
defaults.rateWindow = 1;
defaults.smoothing = 6;
defaults.repetitions = 10;
defaults.randomize = true;
session.startExperimentalTask(defaults,result.metadata);
for k = 1:3500
    if ~session.Recording, break; end
    session.advanceSimulation();
end
assert(~session.Recording && strcmp(session.LastRecording.task.completion,'complete'));
assert(numel(session.LastRecording.task.trials)==30);
assert(all([session.LastRecording.task.trials.targetHit]));
session.stop();
disp('Experimental task scoring, UI, simulation and MAT save passed.');

    function step(rate)
        spikes = false(100,2);
        for axisIndex=1:2, spikes(1:round(rate(axisIndex)*10),axisIndex) = true; end
        t = t+0.1;
        task.step(spikes,t);
    end

    function setValue(name,value)
        field = findall(window,'Tag',['task_' name]);
        field.Value = value;
    end
end

function click(button)
assert(isscalar(button) && strcmp(button.Enable,'on'),'Button unavailable.');
callback = button.ButtonPushedFcn;
callback(button,[]);
drawnow;
end
