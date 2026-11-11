classdef MotorUnitTargetTask < handle
    % Sample-clock trial logic, independent of rendering and device callbacks.
    properties (SetAccess=private)
        Settings
        Schedule
        Phase = 'rest'
        Trial = 1
        Trials = struct([])
        Time = zeros(0,1)
        RawRates = zeros(0,2)
        Rates = zeros(0,2)
        Cursor = zeros(0,2)
        FrameTrial = zeros(0,1)
        FramePhase = cell(0,1)
        InTarget = false(0,3)
        InAngle = false(0,3)
        Completion = ''
        RestHeld = 0
        TargetHeld = 0
        AngleHeld = 0
        TrialStart = NaN
    end
    properties (Access=private)
        RateState = []
        RestSince = NaN
        TargetSince = nan(1,3)
        AngleSince = nan(1,3)
        TargetHits = zeros(1,3)
        AngleHits = zeros(1,3)
        TargetEvents = {[],[],[]}
        AngleEvents = {[],[],[]}
        ClosestDistance = Inf
        ClosestPosition = [NaN NaN]
        TrialFirstFrame = 0
        LastTime = 0
        SampleRate
    end
    properties (Constant)
        Targets = [1 0;1 1;0 1]
        TargetNames = {'TI: Motor unit 1','TII: Both motor units','TIII: Motor unit 2'}
        AxisMax = 1.25
    end
    methods
        function obj = MotorUnitTargetTask(settings,fs)
            if ~isfield(settings,'cursorHistory'), settings.cursorHistory = 1; end
            validateattributes(settings.mu,{'numeric'},{'vector','numel',2,'integer','positive'});
            assert(settings.mu(1) ~= settings.mu(2),'Choose two different motor units.');
            for field = {'referencePPS','gain'}
                validateattributes(settings.(field{1}),{'numeric'}, ...
                    {'vector','numel',2,'positive','finite','real'});
                settings.(field{1}) = reshape(settings.(field{1}),1,2);
            end
            for field = {'targetRadius','angleInnerRadius','targetHold','angleHold', ...
                    'timeout','restTime','restRadius','rateWindow','cursorHistory'}
                validateattributes(settings.(field{1}),{'numeric'},{'scalar','positive','finite','real'});
            end
            assert(settings.targetRadius < 0.25,'Target radius must be below 0.25.');
            assert(settings.angleInnerRadius < 1-settings.targetRadius, ...
                'Angle inner radius must be smaller than the near edge of the axis targets.');
            assert(settings.restRadius < settings.angleInnerRadius,'Rest radius must be smaller than the angle inner radius.');
            assert(max(settings.targetHold,settings.angleHold) < settings.timeout, ...
                'Hold durations must be shorter than the trial timeout.');
            for field = {'repetitions','smoothing','seed'}
                validateattributes(settings.(field{1}),{'numeric'}, ...
                    {'scalar','integer','finite','nonnegative'});
            end
            assert(settings.repetitions >= 1 && settings.smoothing >= 1,'Repetitions and smoothing must be at least 1.');
            assert(settings.seed <= 2^32-1,'Seed must be at most 4294967295.');
            validateattributes(fs,{'numeric'},{'scalar','positive','finite'});
            obj.Settings = settings;
            obj.SampleRate = fs;
            obj.Schedule = repmat(1:3,1,settings.repetitions);
            if settings.randomize
                rngStream = RandStream('mt19937ar','Seed',settings.seed);
                obj.Schedule = obj.Schedule(randperm(rngStream,numel(obj.Schedule)));
            end
        end

        function step(obj,spikes,t)
            if ~isempty(obj.Completion), return; end
            s = obj.Settings;
            dt = size(spikes,1)/obj.SampleRate;
            assert(dt > 0 && abs(t-obj.LastTime-dt) < 1e-7,'Task requires consecutive EMG sample windows.');
            obj.LastTime = t;
            [obj.RateState,raw,rate,eligible] = obj.estimateRates( ...
                obj.RateState,spikes(:,s.mu),dt,s.rateWindow,s.smoothing);
            p = rate./s.referencePPS.*s.gain;
            obj.Time(end+1,1) = t;
            obj.RawRates(end+1,:) = raw;
            obj.Rates(end+1,:) = rate;
            obj.Cursor(end+1,:) = p;
            obj.FrameTrial(end+1,1) = obj.Trial;
            obj.FramePhase{end+1,1} = obj.Phase;
            obj.InTarget(end+1,:) = false;
            obj.InAngle(end+1,:) = false;
            if strcmp(obj.Phase,'rest')
                [obj.RestSince,obj.RestHeld] = obj.dwell(eligible && norm(p)<=s.restRadius,obj.RestSince,t);
                if obj.RestHeld >= s.restTime-1e-9
                    obj.Phase = 'attempt';
                    obj.TrialStart = t;
                    obj.TrialFirstFrame = numel(obj.Time)+1;
                end
                return;
            end
            if t-obj.TrialStart > s.timeout+1e-9
                obj.finishTrial('timeout',obj.TrialStart+s.timeout);
                return;
            end
            active = obj.Schedule(obj.Trial);
            for k = 1:3
                center = obj.Targets(k,:);
                inTarget = norm(p-center) <= s.targetRadius;
                projection = dot(p,center)/norm(center);
                perpendicular = abs(p(1)*center(2)-p(2)*center(1))/norm(center);
                halfAngle = asin(s.targetRadius/norm(center));
                inAngle = norm(p)>=s.angleInnerRadius && projection>0 && all(p<=obj.AxisMax) && ...
                    perpendicular <= projection*tan(halfAngle);
                obj.InTarget(end,k) = inTarget;
                obj.InAngle(end,k) = inAngle;
                [obj.TargetSince(k),targetHeld] = obj.dwell(inTarget,obj.TargetSince(k),t);
                [obj.AngleSince(k),angleHeld] = obj.dwell(inAngle,obj.AngleSince(k),t);
                if inTarget && targetHeld >= s.targetHold-1e-9 && ...
                        (isempty(obj.TargetEvents{k}) || obj.TargetEvents{k}(end)<obj.TargetSince(k))
                    obj.TargetHits(k) = obj.TargetHits(k)+1;
                    obj.TargetEvents{k}(end+1) = t;
                end
                if inAngle && angleHeld >= s.angleHold-1e-9 && ...
                        (isempty(obj.AngleEvents{k}) || obj.AngleEvents{k}(end)<obj.AngleSince(k))
                    obj.AngleHits(k) = obj.AngleHits(k)+1;
                    obj.AngleEvents{k}(end+1) = t;
                end
                if k==active, obj.TargetHeld = targetHeld; obj.AngleHeld = angleHeld; end
            end
            idx = find(obj.Time(obj.TrialFirstFrame:end) <= t-s.targetHold+1e-9,1,'last');
            if ~isempty(idx)
                point = mean(obj.Cursor(obj.TrialFirstFrame+idx-1:end,:),1);
                distance = norm(point-obj.Targets(active,:));
                if distance < obj.ClosestDistance
                    obj.ClosestDistance = distance;
                    obj.ClosestPosition = point;
                end
            end
            if obj.TargetHits(active)>0
                obj.finishTrial('hit',t);
            elseif t-obj.TrialStart >= s.timeout-1e-9
                obj.finishTrial('timeout',t);
            end
        end

        function abort(obj,reason)
            if ~isempty(obj.Completion), return; end
            if strcmp(obj.Phase,'attempt')
                obj.finishTrial('aborted',obj.LastTime);
            end
            obj.Completion = reason;
            obj.Phase = 'finished';
        end

        function state = snapshot(obj)
            state = struct('phase',obj.Phase,'trial',obj.Trial,'total',numel(obj.Schedule), ...
                'target',obj.Schedule(obj.Trial),'restHeld',obj.RestHeld, ...
                'targetHeld',obj.TargetHeld,'angleHeld',obj.AngleHeld, ...
                'remaining',obj.Settings.timeout,'completion',obj.Completion, ...
                'cursor',[NaN NaN],'rates',[NaN NaN],'trail',zeros(0,2), ...
                'lastOutcome','','lastTarget',NaN,'lastAngleHit',false, ...
                'angleHit',obj.AngleHits(obj.Schedule(obj.Trial))>0);
            if ~isempty(obj.Trials)
                state.lastOutcome = obj.Trials(end).outcome;
                state.lastTarget = obj.Trials(end).target;
                state.lastAngleHit = obj.Trials(end).angleHit;
            end
            if ~isempty(obj.Time)
                state.cursor = obj.Cursor(end,:);
                state.rates = obj.Rates(end,:);
                state.trail = obj.Cursor(obj.Time>=obj.Time(end)-obj.Settings.cursorHistory,:);
                if strcmp(obj.Phase,'attempt')
                    state.remaining = max(0,obj.Settings.timeout-(obj.Time(end)-obj.TrialStart));
                end
            end
        end

        function data = export(obj)
            data = struct('settings',obj.Settings,'schedule',obj.Schedule, ...
                'targets',obj.Targets,'trials',obj.Trials,'completion',obj.Completion, ...
                'timeSec',obj.Time,'rawRatePPS',obj.RawRates,'ratePPS',obj.Rates, ...
                'rawCursorXY',obj.RawRates./obj.Settings.referencePPS.*obj.Settings.gain, ...
                'cursorXY',obj.Cursor,'frameTrial',obj.FrameTrial,'framePhase',{obj.FramePhase}, ...
                'inTarget',obj.InTarget,'inAngle',obj.InAngle,'axisMax',obj.AxisMax);
        end
    end
    methods (Access=private)
        function finishTrial(obj,outcome,t)
            active = obj.Schedule(obj.Trial);
            distance = obj.ClosestDistance;
            if ~isfinite(distance), distance = NaN; end
            trial = struct('number',obj.Trial,'target',active,'startSec',obj.TrialStart, ...
                'endSec',t,'outcome',outcome,'targetHit',obj.TargetHits(active)>0, ...
                'angleHit',obj.AngleHits(active)>0,'targetHitCounts',obj.TargetHits, ...
                'angleHitCounts',obj.AngleHits,'targetHitTimes',{obj.TargetEvents}, ...
                'angleHitTimes',{obj.AngleEvents},'nearestPosition',obj.ClosestPosition, ...
                'nearestDistance',distance,'timeToTargetSec',NaN);
            if trial.targetHit, trial.timeToTargetSec = obj.TargetEvents{active}(1)-obj.TrialStart; end
            if isempty(obj.Trials), obj.Trials = trial; else, obj.Trials(end+1) = trial; end
            if strcmp(outcome,'aborted'), return; end
            if obj.Trial==numel(obj.Schedule)
                obj.Phase = 'finished';
                obj.Completion = 'complete';
                return;
            end
            obj.Trial = obj.Trial+1;
            obj.Phase = 'rest';
            obj.RestSince = NaN;
            obj.RestHeld = 0;
            obj.TargetSince(:) = NaN;
            obj.AngleSince(:) = NaN;
            obj.TargetHits(:) = 0;
            obj.AngleHits(:) = 0;
            obj.TargetEvents = {[],[],[]};
            obj.AngleEvents = {[],[],[]};
            obj.TargetHeld = 0;
            obj.AngleHeld = 0;
            obj.ClosestDistance = Inf;
            obj.ClosestPosition = [NaN NaN];
        end
    end
    methods (Static)
        function [state,raw,rate,ready] = estimateRates(state,spikes,dt,window,smoothing)
            if isempty(state)
                state = struct('counts',zeros(0,2),'durations',zeros(0,1),'history',zeros(0,2));
            end
            state.counts(end+1,:) = sum(spikes ~= 0,1);
            state.durations(end+1,1) = dt;
            while numel(state.durations)>1 && sum(state.durations(2:end))>=window-1e-9
                state.counts(1,:) = [];
                state.durations(1) = [];
            end
            covered = sum(state.durations);
            raw = sum(state.counts,1)/covered;
            state.history(end+1,:) = raw;
            state.history = state.history(max(1,end-smoothing+1):end,:);
            rate = mean(state.history,1);
            ready = covered>=window-1e-9 && size(state.history,1)>=smoothing;
        end
    end
    methods (Static,Access=private)
        function [since,held] = dwell(inside,since,t)
            if ~inside, since = NaN; held = 0; return; end
            if isnan(since), since = t; end
            held = t-since;
        end
    end
end
