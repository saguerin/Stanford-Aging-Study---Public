function am_univariate_face_scene_study4(subID,sessions2include)

start_dir = pwd;

spm('Defaults','fMRI');
spm_jobman('initcfg');

% TO DO:
% - Add covariate of no interest for session effects
% - Need to add Michael's artifact regressor - can wait till more
% complicated analyses
% - Should be possible to have a variable # of runs provided that they are named
%   1-4 in onset file.
% (Exclusion of trials/onsets is based on edits to onsets file)
% - I have added code to remove decompressed files after the analysis is complete.
%   However, I have not added a '-f' flag as a precaution and will need to test

% - What script needs to be run to generate Valerie's lovely CSV files? Ask
% Monica. Will need more complicated files for SubMem. Meet with Monica.
% - Do we enter the duration as 4 or 0? I have been using 4.
% - remove high pass filter

study_or_test = 'study';

analysis_directory = 'face_scene_study'; % this directory will be created and all files will be written there
onsets_file = 'study.csv'; % in behav directory

cond_names = {'Face','Scene'}

% We can include more than one condition label in these cell arrays in
% order to combine bins. Labels must correspond to those used in the onsets
% file (e.g., study.csv).
condition_labels{1} = {'WF'};
condition_labels{2} = {'WP'};

stim_duration = 4;
TR = 2;

% Should generally not have to edit below this line (except contrasts section)
% -------------------------------------------------------------------------
% -------------------------------------------------------------------------
% -------------------------------------------------------------------------
% Get directory info:
subDir = ['/share/awagner/AM/data/' subID '/univariate/' analysis_directory];
mkdir(subDir);

cd(subDir);
! rm SPM.mat

% Load onsets - get num of conditions and sessions to include
num_conditions = length(condition_labels);

onsets_file_path = ['/share/awagner/AM/data/' subID '/behav/' onsets_file];
onsets_table = readtable(onsets_file_path);

sessions2include = unique(table2array(onsets_table(:,1)));

% Concatenate files across sessions and decompress for SPM
files = {};
vols_per_sess = zeros(1,max(sessions2include));
for session_num = sessions2include;
    file2unzip = char(['/share/awagner/AM/analysis/' study_or_test '/' subID '/reg/epi/'...
        'unsmoothed/run_' num2str(session_num) '/timeseries_xfm.nii.gz']);

    base_filename = char(['/share/awagner/AM/analysis/' study_or_test '/' subID '/reg/epi/'...
        'unsmoothed/run_' num2str(session_num) '/timeseries_xfm.nii']);

    % See if the file has already be unzipped. If not, unzip
    % Keep original compressed file
    if ~exist(base_filename, 'file')
        cmd = ['! gunzip -k ' file2unzip];
        disp(['Decompressing ' file2unzip])
        eval(cmd)
    end

    % Check # of TRs. We need this for onsets and session covariates.
    % Some runs are missing a TR at the end
    vol = spm_vol(base_filename);
    this_num_vol = size(vol,1);
    vols_per_sess(session_num) = this_num_vol;

    % List of files we'll use for SPM
    files = vertcat(files{:},...
        cellstr([(repmat([base_filename ','],this_num_vol, 1))...
        char(cellstr(num2str((1:this_num_vol)','%-d')))]));
end
clear vol

% Handle onsets
% Initialize onsets to empty vectors
for condition = 1:num_conditions;
    onsets{1}.cond{condition} = [];
end

% Concatenate onsets across sessions
first_onset_of_this_session(1) = 0;
for session_num = sessions2include;
    session_rows = find(table2array(onsets_table(:,1))==session_num);

    for condition = 1:num_conditions;
        for label = condition_labels{condition};
            label_rows = find(strcmp(table2array(onsets_table(:,2)),label));
            rows2use = intersect(session_rows,label_rows);

            new_onsets = table2array(onsets_table(rows2use,3))+first_onset_of_this_session(session_num);

            onsets{1}.cond{condition} =...
                [onsets{1}.cond{condition}; new_onsets];
        end

    first_onset_of_this_session(session_num+1) = first_onset_of_this_session(session_num) + vols_per_sess(session_num)*TR; % 298 s per BOLD run
    end

end

% Concatenate motion parameters across sessions
for motion_regressor = 1:6;
    motion_par_conc{motion_regressor} = [];
end

for session_num = sessions2include;
    motion_file = ['/share/awagner/AM/analysis/' study_or_test '/' subID...
        '/preproc/run_' num2str(session_num) '/realignment_params.csv'];
    motion_par = readtable(motion_file);
    motion_par = motion_par(:,2:7); % dropping first col and end cols
    motion_par = table2array(motion_par);

    for motion_regressor = 1:6;
        motion_par_conc{motion_regressor} =...
            [motion_par_conc{motion_regressor}; motion_par(:,motion_regressor)];
    end
end

% Add artifact regressor (a separate predictor/beta for each TR with an
% artifact)
big_art_table = []; % just in case
for session_num = sessions2include;
  artifact_file = ['/share/awagner/AM/analysis/' study_or_test '/' subID...
      '/preproc/run_' num2str(session_num) '/artifacts.csv'];
  if session_num == 1;
    big_art_table = readtable(artifact_file)
  else
    little_art_table = readtable(artifact_file)
    big_art_table = [big_art_table; little_art_table]
  end
end

% Sum across all types of artifacts (motion, spike, global intensity)
artifact_vector = sum(artifact_array, 2);
TRs_with_artifacts = find(artifact_vector > 0);

# Form matrix of artifacts covariates.
if length(TRs_with_artifacts)>0;
    artifacts_regressors = zeros(numTRs, len(TRs_with_artifacts));
    col = 1;
    keyboard % make sure that TRs_with_artifacts is a row vector
    for this_TR = TRs_with_artifacts;
      artifacts_regressors(this_TR, col) = 1;
      col = col + 1;
    end
end

% Model Specification
%--------------------------------------------------------------------------
matlabbatch{1}.spm.stats.fmri_spec.dir = {subDir};
matlabbatch{1}.spm.stats.fmri_spec.timing.units = 'secs';
matlabbatch{1}.spm.stats.fmri_spec.timing.RT = 2;
matlabbatch{1}.spm.stats.fmri_spec.timing.fmri_t = 16;
matlabbatch{1}.spm.stats.fmri_spec.timing.fmri_t0 = 8;
% matlabbatch{1}.spm.stats.fmri_spec.bases.hrf.derivs = [1 0];

matlabbatch{1}.spm.stats.fmri_spec.sess(1).scans = files;

for condition = 1:num_conditions;
    matlabbatch{1}.spm.stats.fmri_spec.sess(1).cond(condition).name =...
        cond_names{condition};
    matlabbatch{1}.spm.stats.fmri_spec.sess(1).cond(condition).onset =...
        onsets{1}.cond{condition};
    matlabbatch{1}.spm.stats.fmri_spec.sess(1).cond(condition).duration =...
        stim_duration;
end

for motion_regressor = 1:6;
    matlabbatch{1}.spm.stats.fmri_spec.sess(1).regress(motion_regressor).name =...
        ['Motion_Reg_' num2str(motion_regressor)];
    matlabbatch{1}.spm.stats.fmri_spec.sess(1).regress(motion_regressor).val  =...
        motion_par_conc{motion_regressor};
end
last_reg_num = 6;

# Add artifact regressors if necessary - PROOF READ
if length(TRs_with_artifacts)>0;
  for art_regressor = 1:length(TRs_with_artifacts)
    matlabbatch{1}.spm.stats.fmri_spec.sess(1).regress(last_reg_num+1).name =...
        ['Art_Reg_' num2str(art_regressor)];
    matlabbatch{1}.spm.stats.fmri_spec.sess(1).regress(last_reg_num+1).val  =...
        artifacts_regressors(:, art_regressor);

    last_reg_num = last_reg_num + 1;
  end
end



# NEXT STEP - ADD SESSION EFFECTS

% Model Estimation
%--------------------------------------------------------------------------
matlabbatch{2}.spm.stats.fmri_est.spmmat = cellstr([subDir '/SPM.mat']);

% Contrasts
%--------------------------------------------------------------------------
matlabbatch{3}.spm.stats.con.spmmat = cellstr([subDir '/SPM.mat']);
matlabbatch{3}.spm.stats.con.delete = 0;

matlabbatch{3}.spm.stats.con.consess{1}.tcon.name = 'Stim-Baseline';
matlabbatch{3}.spm.stats.con.consess{1}.tcon.weights = [.5 .5];
matlabbatch{3}.spm.stats.con.consess{1}.sessrep = 'none';

matlabbatch{3}.spm.stats.con.consess{2}.tcon.name = 'Face-Scene';
matlabbatch{3}.spm.stats.con.consess{2}.tcon.weights = [1 -1];
matlabbatch{3}.spm.stats.con.consess{2}.sessrep = 'none';

% Run the Job
%--------------------------------------------------------------------------
save matlabbatch matlabbatch
spm_jobman('run',matlabbatch);

% Remove decompressed data (keep compressed) to save storage space
%--------------------------------------------------------------------------
for session_num = sessions2include;
  base_filename = char(['/share/awagner/AM/analysis/' study_or_test '/' subID '/reg/epi/'...
    'unsmoothed/run_' num2str(session_num) '/timeseries_xfm.nii']);

  cmd = ['! rm ' base_filename];
  disp(['Removing decompressed file ' base_filename])
  eval(cmd)
end

cd(start_dir);