function signal = hyser2MUedit(emg, force)

signal.data = emg;
signal.fsamp = 2048;
signal.nChan = 256;
signal.ngrid = 4;
signal.gridname = {'hysergrids' 'hysergrids' 'hysergrids' 'hysergrids'}; % 8x8 topology, specified within the formatsignalHDEMG.m function
signal.muscle = {'posterior forearm - distal', 'posterior forearm - proximal', 'anterior forearm - distal', 'anterior forearm - proximal'};
signal.path = force;