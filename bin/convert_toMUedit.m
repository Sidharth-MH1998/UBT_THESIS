signal.data = recordedEMG;      % channels x time
signal.fsamp = 2000;
signal.nChan = size(recordedEMG,1);
signal.ngrid = 2;
signal.gridname = {'GR08MM1305','GR08MM1305'};
signal.muscle = {'Muscle 1','Muscle 2'};

% Optional, only if available:
%signal.target = target_signal(:)';
%signal.path   = path_signal(:)';