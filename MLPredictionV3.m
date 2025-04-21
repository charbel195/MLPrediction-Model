
% Enhanced LSBoost Training Script with Modular Design, 5-Fold Cross-Validation, Hold-Out Evaluation, and Dual-Target Support
clc; clear; close all;
fprintf('🚀 Starting Enhanced LSBoost Training with 5-Fold CV and Final Hold-Out Evaluation...\n');

%% --------------------- Data Preparation ---------------------
data = readtable('AR_data2.xlsx');
if isempty(data), error('Data file not found or empty.'); end
data = rmmissing(data);

% Feature Engineering
fprintf("🛠️ Performing feature engineering...\n");
data.Delta_LC_LA = data.LCeq - data.LAeq;
data.Leq63Hz_LAeq_Ratio = data.Leq63Hz ./ (data.LAeq + eps);
data.LZFmax_LCFmax_Ratio = data.LZFmax ./ (data.LCFmax + eps);
data.log_Leq63Hz = log(data.Leq63Hz + eps);
data.TotalNoiSeQ = data.HNoiSeQ + data.CNoiSeQ;
data.Delta_ZF_CF = data.LZF99 - data.LCF90;
data.LAeq_HNoiSeQ = data.LAeq .* data.HNoiSeQ;
data.Leq63Hz_HNoiSeQ = data.Leq63Hz .* data.HNoiSeQ;
data.LZF99_LCFmax_Ratio = data.LZF99 ./ (data.LCFmax + eps);
data.LCFmax_CNoiSeQ = data.LCFmax .* data.CNoiSeQ;
data.LZFmax_LAeq_Ratio = data.LZFmax ./ (data.LAeq + eps);
data.LZF99_HNoiSeQ = data.LZF99 .* data.HNoiSeQ;
data.LZFmax_LCF90_Ratio = data.LZFmax ./ (data.LCF90 + eps);

% Feature selection
preFeatures = {'LAeq','LCeq','Leq63Hz','HNoiSeQ','CNoiSeQ', ...
               'Delta_LC_LA','Leq63Hz_LAeq_Ratio', ...
               'TotalNoiSeQ','LAeq_HNoiSeQ','Leq63Hz_HNoiSeQ'};

liveFeatures = [preFeatures, {'LZF99','LCFmax','LZFmax','LCF90', ...
                'LZFmax_LCFmax_Ratio','Delta_ZF_CF','LZF99_LCFmax_Ratio', ...
                'LCFmax_CNoiSeQ','LZFmax_LAeq_Ratio','LZF99_HNoiSeQ','LZFmax_LCF90_Ratio'}];

% Convert and normalize features
data.AR = table2array(data(:,"AR"));
data.DR = table2array(data(:,"DR"));
% X_pre = zscore(table2array(data(:, preFeatures)));
% X_live = zscore(table2array(data(:, liveFeatures)));
[X_pre, mu_pre, sigma_pre] = zscore(table2array(data(:, preFeatures)));
[X_live, mu_live, sigma_live] = zscore(table2array(data(:, liveFeatures)));
Y = [data.AR, data.DR];

save('pre_scaling.mat', 'mu_pre', 'sigma_pre');
save('live_scaling.mat', 'mu_live', 'sigma_live');



% Set common axis limits for all scatter plots
yMin = floor(min(Y(:)) - 0.5);
yMax = ceil(max(Y(:)) + 0.5);

%% --------------------- Final Hold-Out Split ---------------------
rng(42);
cvHoldout = cvpartition(size(data,1), 'HoldOut', 0.2);
Xtest_pre = X_pre(test(cvHoldout),:);
Xtrain_pre = X_pre(training(cvHoldout),:);
Xtest_live = X_live(test(cvHoldout),:);
Xtrain_live = X_live(training(cvHoldout),:);
Ytest = Y(test(cvHoldout),:);
Ytrain = Y(training(cvHoldout),:);

%% --------------------- Model Training and Evaluation ---------------------
trainEvaluateFinal(Xtrain_pre, Ytrain(:,1), Xtest_pre, Ytest(:,1), preFeatures, 'PreFestival AR', yMin, yMax);
trainEvaluateFinal(Xtrain_pre, Ytrain(:,2), Xtest_pre, Ytest(:,2), preFeatures, 'PreFestival DR', yMin, yMax);
trainEvaluateFinal(Xtrain_live, Ytrain(:,1), Xtest_live, Ytest(:,1), liveFeatures, 'Live AR', yMin, yMax);
trainEvaluateFinal(Xtrain_live, Ytrain(:,2), Xtest_live, Ytest(:,2), liveFeatures, 'Live DR', yMin, yMax);

%% --------------------- Functions ---------------------
function trainEvaluateFinal(X_train, Y_train, X_test, Y_test, featureNames, label, yMin, yMax)
    fprintf('\n🔁 Starting 5-Fold Cross-Validation for %s...\n', label);
    cv = cvpartition(size(X_train,1), 'KFold', 5);
    R2_scores = zeros(cv.NumTestSets,1);
    bestR2 = -Inf;
    bestModel = [];

    for i = 1:cv.NumTestSets
        idxTrain = training(cv, i);
        idxVal = test(cv, i);

        model = fitrensemble(X_train(idxTrain,:), Y_train(idxTrain), 'Method', 'LSBoost', ...
            'OptimizeHyperparameters', {'NumLearningCycles','LearnRate','MinLeafSize','MaxNumSplits'}, ...
            'HyperparameterOptimizationOptions', struct('MaxObjectiveEvaluations', 70, ...
            'AcquisitionFunctionName', 'expected-improvement-plus', 'Verbose', 0));

        Y_val_pred = predict(model, X_train(idxVal,:));
        R2 = 1 - sum((Y_train(idxVal) - Y_val_pred).^2) / sum((Y_train(idxVal) - mean(Y_train(idxVal))).^2);
        R2_scores(i) = R2;

        if R2 > bestR2
            bestR2 = R2;
            bestModel = model;
        end

        fprintf("  Fold %d -> R²: %.4f\n", i, R2);
    end

    meanR2 = mean(R2_scores);
    fprintf("\n✅ Average R² across folds for %s: %.4f\n", label, meanR2);

    % Extract best hyperparameters
    bestParams = bestModel.HyperparameterOptimizationResults.XAtMinObjective;
    nTrees = bestParams.NumLearningCycles;
    lr = bestParams.LearnRate;
    leaf = bestParams.MinLeafSize;
    split = bestParams.MaxNumSplits;

    % Retrain final model on all training data
    tree = templateTree('MinLeafSize', leaf, 'MaxNumSplits', split);
    model_final = fitrensemble(X_train, Y_train, 'Method', 'LSBoost', ...
        'NumLearningCycles', nTrees, 'LearnRate', lr, 'Learners', tree);

    % Final Evaluation on Hold-Out Test Set
    Y_test_pred = predict(model_final, X_test);
    Y_train_pred = predict(model_final, X_train);

    MAE_train = mean(abs(Y_train - Y_train_pred));
    RMSE_train = sqrt(mean((Y_train - Y_train_pred).^2));
    R2_train = 1 - sum((Y_train - Y_train_pred).^2) / sum((Y_train - mean(Y_train)).^2);

    MAE_test = mean(abs(Y_test - Y_test_pred));
    RMSE_test = sqrt(mean((Y_test - Y_test_pred).^2));
    R2_test = 1 - sum((Y_test - Y_test_pred).^2) / sum((Y_test - mean(Y_test)).^2);

    fprintf("\n📊 [%s - Final Hold-Out Evaluation]\n", label);
    fprintf("  MAE - Training Set : %.4f\n", MAE_train);
    fprintf("  RMSE - Training Set: %.4f\n", RMSE_train);
    fprintf("  R²   - Training Set: %.4f\n", R2_train);
    fprintf("  MAE - Test Set     : %.4f\n", MAE_test);
    fprintf("  RMSE - Test Set    : %.4f\n", RMSE_test);
    fprintf("  R²   - Test Set    : %.4f\n", R2_test);

    % Feature Importance
    importance = predictorImportance(model_final);
    [~, idx] = sort(importance, 'descend');
    fprintf("\n📌 Feature Importance for %s:\n", label);
    for i = 1:length(idx)
        fprintf("  %-25s %.6f\n", featureNames{idx(i)}, importance(idx(i)));
    end

    % Save scatter plots
    figure('Name', label, 'NumberTitle', 'off');
    subplot(1,2,1)
    scatter(Y_train, Y_train_pred, 'filled');
    hold on; plot([yMin, yMax], [yMin, yMax], 'r--');
    xlabel('Actual'); ylabel('Predicted');
    title([label ' - Training']);
    grid on; axis([yMin yMax yMin yMax]);

    subplot(1,2,2)
    scatter(Y_test, Y_test_pred, 'filled');
    hold on; plot([yMin, yMax], [yMin, yMax], 'r--');
    xlabel('Actual'); ylabel('Predicted');
    title([label ' - Test']);
    grid on; axis([yMin yMax yMin yMax]);

    saveas(gcf, [label '_scatter_plot.png']);

% Save best model under expected name for UI
if contains(label, 'PreFestival AR')
    model_Pre_AR = model_final;
    save('BestMLModel_Pre_AR.mat', 'model_final');
elseif contains(label, 'PreFestival DR')
    model_Pre_DR = model_final;
    save('BestMLModel_Pre_DR.mat', 'model_final');
elseif contains(label, 'Live AR')
    model_Live_AR = model_final;
    save('BestMLModel_Live_AR.mat', 'model_final');
elseif contains(label, 'Live DR')
    model_Live_DR = model_final;
    save('BestMLModel_Live_DR.mat', 'model_final');
end

end
