# Decomposition comparison — 28 September 2026

## Conclusion from completed controlled runs

**On this recording, with identical requested settings and RNG state, decompose3 and decompose4 produce the same six motor units and exactly the same discharge sample indices.** All 50 extraction attempts completed successfully in both functions.

| MU | decompose3 spikes | decompose4 spikes | Agreement |
|---:|---:|---:|---:|
| 1 | 351 | 351 | 100% |
| 2 | 432 | 432 | 100% |
| 3 | 313 | 313 | 100% |
| 4 | 544 | 544 | 100% |
| 5 | 548 | 548 | 100% |
| 6 | 798 | 798 | 100% |

Exact array comparisons, beyond the 1 ms matching tolerance, confirmed identical MUPulses, spike_train, peaks, MUFilters, SIL, CoV, MUAPs, p2ps, MU_locs, eigenvalues/eigenvectors and whitening matrices. The only numerical difference among the common output fields is floating-point rounding in firing rates: decompose3 evaluates (1./interval)*fs whereas decompose4 evaluates fs./interval. The maximum mean_fr difference was 3.55e-15 Hz, which has no practical significance.

The controlled runs both had six entries in every checked per-unit field. The older decompose3 count bug did not occur in this configuration. This does not prove the functions behave identically for every input or with refinement enabled.

The user's pasted independent run reports the same six spike counts and 100% agreement. Their timings were 482.28 s and 363.62 s; this audit's timings were 427.01 s and 473.15 s. Thus these measurements do not support a claim that either function is intrinsically faster; machine load and execution conditions differ.

Audit results: `tmp/full_comparison_baseline.mat`; complete console evidence: `tmp/full_comparison.log`. MATLAB Code Analyzer returned no findings for the comparison script. Historical differences are explained by unmatched settings and processing stages, remaining random state, and an independently confirmed output-count issue in a prior decompose3 result. They are not evidence of different extracted units under the controlled configuration.

## Recording and method

The screenshot matches `2292026222222222_decomposed4.mat`: six units, 192 channels, 80,160 samples, and the same SIL values. Its stored raw data is exactly equal to `signal.data` in `2292026222222222.mat`. This is 40.08 seconds at 2,000 Hz.

Both current functions are run on that raw recording with the user's requested parameters: fs=2000, badchan=[], padLen=200, initialization=0, NITER=50, nbextchan=1024, silthr=0.9, covfilter=1, covthr=0.5, differentialmode=0, peeloff_flag=1, peeloffwin=0.025 seconds, duplicatesthresh=0.3, CoVDR=0.3, contrastfunc='skew', refineMU=0, preproc_flag=1. The RNG is reset to rng(1,'twister') before each function. The same helper files are used for both.

The controlled comparison checks exact equality of common fields as well as one-to-one discharge agreement within 2 samples (1 ms). Matching agreement is matched_spikes/(spikes_A+spikes_B-matched_spikes). This is agreement between outputs, not ground-truth accuracy.

## Previously saved results

| Result | Discharge-time units | Pulse-train rows | Filter columns | Padding | Initialization | CoV rejection | Refinement |
|---|---:|---:|---:|---:|---:|---:|---:|
| Earlier decompose3 (`tp287f...`) | 11 | 11 | 11 | 0 | 1, random | off | off |
| Latest decompose3 (`tp84c...`) | 11 | 12 | 12 | 0 | 0, activity | off | off |
| Screenshot decompose4 | 6 | 6 | 6 | 200 | 0, activity | on, 0.5 | on |

The older decompose3 file used nbextchan=1000; the other two used 1024. With 192 included channels, both values yield round(nbextchan/192)=5 delayed copies, i.e. 960 extended channels. This difference alone does not change extension dimensions.

The decompose3 saved files do not store their raw input, so their exact input identity cannot be proven from those files alone. Their sample dimensions match the recording. The decompose4 and MUedit files do store raw input, which was checked for exact equality with the identified recording.

## Confirmed reasons for different historical outputs

1. **Different CoV rejection.** Both previous decompose3 runs disabled it. The latest saved CoV array contains six values above 0.5 (approximately 4.262, 0.948, 0.503, 0.545, 2.916, 1.637). Those values would fail the requested quality gate at that stage. This does not mean simply filtering the historical output will reproduce another run: the extraction histories and subsequent processing differ.
2. **Different padding.** Earlier decompose3 runs used zero padding length; the screenshot run used 200 zeros at each end. Padding happens after filtering in both functions. It changes the extended data, covariance/whitening and extraction; it is not extra notch/bandpass edge protection in these implementations.
3. **Different refinement.** The screenshot run used refinement; the decompose3 runs did not. Refinement rebuilds filters, re-detects discharges and removes discharge-rate outliers. It can change timing, pulse amplitude, spike count, MUAPs and firing-rate estimates. Original SIL/CoV fields are not recomputed as final post-refinement quality metrics.
4. **Randomness remains with initialization=0.** getspikes, calcSIL and batchprocessfilters_1win call kmeans without fixed cluster starting centers. The saved screenshot parameters do not record an RNG seed. The current dec3 runner sets rng(1), whereas offlineDecomposition does not reset it. Thus historical reproducibility is not established by initialization=0 alone.
5. **An actual decompose3 output-count bug.** The latest saved result contains 12 rows in peaks and 12 filter columns but only 11 MUPulses, SIL, CoV, MUAP and firing-rate entries. In decompose3.m, the >10-spike rejection compacts discharge times without applying the corresponding rejection to pulse-train rows and filters. The existing first 11 pulse rows have their strongest average discharge amplitudes at the corresponding 11 discharge trains; the extra row is trailing in this saved example. Do not interpret all 12 pulse rows as 12 retained units.

## Additional implementation differences

- decompose3 does not remove/reorder filter columns after duplicate removal. decompose4 matches retained discharge trains to their original filters and quality arrays.
- decompose3 removes filters for SIL<0.9 but keeps SIL entries for SIL>0.9; analogous strict/inclusive differences occur at CoV=0.5. decompose4 uses consistent masks. Exact threshold equality is an edge-case bug, not an established cause of the historical discrepancy.
- decompose3's refinement call passes ones(1,64). Current refineMUs requires one mask entry per input channel, and 1 means exclude. It is unsuitable for this 192-channel input. Both controlled runs leave refinement off, as requested.
- decompose4 adds raw data, sampling frequency, masks, MUedit-compatible timing fields, references and saved parameters. A larger number of structure fields does not indicate more detected motor units.
- Both functions calculate mean_fr by averaging instantaneous rates with a prepended zero. They use mathematically equivalent formulas in a different arithmetic order; only negligible floating-point rounding differed in the controlled run.

## Historical unit correspondence

Comparisons below allow one-to-one coincidence within 1 ms and search a constant offset between -25 and +25 ms. Offset search is useful when independently estimated filters shift source peaks. Percentages are descriptive; no physiological identity or accuracy is guaranteed.

| Latest saved decompose3 MU | Screenshot decompose4 MU | Best discharge agreement |
|---:|---:|---:|
| 1 | 1 | 99.43% |
| 4 | 2 | 100.00% |
| 8 | 3 | 88.58% |
| 9 | 4 | 96.54% |
| 10 | 6 | 75.36% |

Screenshot unit 5 has no strong match in that saved decompose3 output. Several common units have different indices; comparing MU number alone is misleading.

## MUedit saved-file check

`2292026222222222.mat_decomp.mat` and its `_edited.mat` copy have exactly identical Dischargetimes and Pulsetrain fields. Therefore manual editing is not the demonstrated cause for this particular pair.

Both have exactly the same stored raw EMG as the identified recording. Saved settings include initialization=1, refineMU=1, covfilter=1, nbextchan=1000, thresholdtarget=0.9 and edges=0.5. Their metadata specifies three grids, with seven pulse trains on grid 1, none on grid 2, and one on grid 3. That grid-3 entry contains only one discharge; it should not be counted as an established motor unit just because its cell is nonempty. The exact external MUedit decomposition implementation/run history was not reproduced here.

Several screenshot units match MUedit grid-1 units despite different indices and offsets: approximately 99.43%, 99.31%, 96.86%, 81.35% and 59.44% for screenshot units 1, 2, 4, 5 and 6 respectively (matching grid-1 units 1, 2, 3, 6 and 7). Screenshot unit 3 has no strong match there.

## Files and scope

The comparison script is `03_OfflineDecomposition/compare_decompose3_decompose4.m`. Diagnostic scripts, logs and saved analysis are in `tmp/`. No decomposition functions or existing runners were edited.
