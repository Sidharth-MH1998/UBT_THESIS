# Automatic decomposition editing

## Scripts

### [Auto-edit launcher](launch_edit_single_session.m)

`launch_edit_single_session.m` opens a file picker for an existing decomposition and starts automatic editing with motor unit quality filtering enabled.

### [Single-session editor](edit_single_session.m)

`edit_single_session.m` corrects motor unit discharge times for each selected grid and can filter units by silhouette score and interspike interval variability. It saves the edited results in a separate `_auto_edited.mat` file by default.

## Run order

1. Run `launch_edit_single_session.m` and select a decomposition file.
2. The launcher calls `edit_single_session.m` to process and save the edited session.
