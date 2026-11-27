# EMG Decomposition and Biofeedback

MATLAB tools for recording multi-grid EMG and force, extracting motor units, and running real-time biofeedback experiments.

## Folders

| Folder | Purpose |
| --- | --- |
| `000_Library` | Shared functions, I-Spin methods, and plotting utilities. |
| `000_testData/phase 3` | Reference script for communicating with and reading data from Novecento+. |
| [01_PseudoOnlineDecomposition](01_PseudoOnlineDecomposition/README.md) | Replay recorded EMG in blocks and compare results with offline decomposition. |
| [02_DataRecording](02_DataRecording/README.md) | Calibrate force sensors and record Novecento EMG and Arduino force. |
| [03_SignalQC](03_SignalQC/README.md) | Check live or recorded EMG quality and identify potentially bad channels. |
| [04_OfflineDecomposition](04_OfflineDecomposition/README.md) | Extract motor units from recordings using the Decomp 5 launcher. |
| [05_Auto_edit](05_Auto_edit/README.md) | Edit discharge times and filter motor units by quality. |
| [06_onlineDecompositionV3](06_onlineDecompositionV3/README.md) | Run online decomposition, force feedback, quadrant feedback, and experimental tasks. |

The online app's `OnlineDecomposeSrc` folder contains its implementation; `TestScripts` contains hardware-free checks.

## Typical workflow

Record signals → check quality → decompose offline → auto-edit → load the edited result into the online app.

To explore the app without hardware, run `06_onlineDecompositionV3/StartOnlineApp.m` in MATLAB and select **Simulation**. Each main folder has a short README with its entry scripts.
