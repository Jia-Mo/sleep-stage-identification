clear; clc; close all;

%{
% STEP 1: IMPORT AND SYNCHRONIZE ALL DATA
file_names = {'slp01a', 'slp01b', 'slp02a', 'slp02b', 'slp03', 'slp04', 'slp14', 'slp16', 'slp32', 'slp37', 'slp41', 'slp45', 'slp48', 'slp59', 'slp60', 'slp61', 'slp66', 'slp67x'};
sec_per_epoch = 30;
all_data = [];
data = [];

for i=1:size(file_names, 2)
    fprintf('\n\n%s importing...\n', cell2mat(file_names(i)));
    data = import_data(file_names(i), sec_per_epoch);
    all_data = [all_data;data];
end

save('all_data', 'all_data');
%}

%{
% STEP 2: FEATURE EXTRACTION
% load('all_data.mat');
% extractFeatures(all_data);
%}

% STEP 3: BUILD CLASSIFIER MODEL USING PSO AND ELM
%hrv = load('features.mat');
hrv = load('features2class.mat');
hrv = hrv.features2class;

% SPLIT DATA
% 70% training data and 30% testing data using stratified sampling
nClasses = 2; % jumlah kelas ouput
trainingData = [];
testingData = [];
for i=1:nClasses
    ithClassInd = find(hrv(:, end) == i);
    nithClass = ceil(size(ithClassInd, 1)*0.7);
    trainingData = [trainingData; hrv(ithClassInd(1:nithClass), :)];
    testingData = [testingData; hrv(ithClassInd(nithClass+1:end), :)];
end

% Particle Swarm Optimization (PSO) process
max_iteration = 10; 
nParticles = 20; % ganti-ganti
nFeatures = 17;
maxTrainingDataBin = size(trainingData, 1);
nBits = size(decToBin(maxTrainingDataBin), 2); %bin2 = de2bi(nSamples);

% Population Initialization: [FeatureMask HiddenNode]
population = rand(nParticles, nFeatures+nBits) > 0.8; % check whether the value is more than sample data
for i=1:nParticles
    while binToDec(population(i, nFeatures+1:end)) < nFeatures || binToDec(population(i, nFeatures+1:end)) > size(trainingData, 1) || sum(population(i, 1:nFeatures)) == 0
        population(i, :) = rand(1, nFeatures+nBits) > 0.8;
    end
    %fprintf('%d=%d\n', i, binToDec(population(i, nFeatures+1:end)));
end

fitnessValue = zeros(nParticles, 1);
velocity = int64(zeros(nParticles, 1));
pBest_particle = zeros(nParticles, nFeatures+nBits); % max fitness function
pBest_fitness = repmat(-1000000, nParticles, 1);
gBest_particle = zeros(1, nFeatures+nBits); % max fitness function all particle all iteration
gBest_fitness = -1000000;
%featureMask = [1 1 1 1 0  1 1 0 0 1  1 1 1 0 0  0 0];
%featureMask = [1 1 1 1 1  1 1 1 1 1  1 1 1 1 1  1 1];
fprintf('Initialization:\n');
fprintf('%8s %15s %15s %15s %15s %15s %20s\n', 'Particle', 'nHiddenNode', 'pBest', 'Time', 'TrainAcc', 'TestAcc', 'SelectedFeatures');
for i=1:nParticles
    tic;
    fprintf('%8d %15d ', i, binToDec(population(i, nFeatures+1:end)));
    % TRAINING
    maskedTrainingFeature = featureMasking(trainingData, population(i, 1:nFeatures));% prepare the feature data (masking)
    trainingTarget = full(ind2vec(trainingData(:,end)'))';% prepare the target data (transformation from 4 into [0 0 0 1 0 0])
    elmModel = trainELM(binToDec(population(i, nFeatures+1:end)), maskedTrainingFeature, trainingTarget);
    
    % TESTING
    maskedTestingFeature = featureMasking(testingData, population(i, 1:nFeatures));% prepare the feature data (masking)
    testingTarget = full(ind2vec(testingData(:,end)'))';% prepare the target data (transformation from 4 into [0 0 0 1 0 0])
    elmModel = testELM(elmModel, maskedTestingFeature, testingTarget);
    fitnessValue(i, 1) = fitness(0.95, 0.05, elmModel.testingAccuracy, population(i, 1:nFeatures));
    
    % pBest Update
    if fitnessValue(i, 1) > pBest_fitness(i, 1)
        pBest_fitness(i, 1) = fitnessValue(i, 1);
        pBest_particle(i, :) = population(i, :);
    end
    endTime = toc;
    fprintf('%15d %15d %15d %15d %4s', pBest_fitness(i, 1), endTime, elmModel.trainingAccuracy, elmModel.testingAccuracy, ' ');
    f = find(population(i, 1:nFeatures)==1);
    for l=1:size(f, 2)
        fprintf('%d ', f(1, l));
    end
    fprintf('\n');
end

% gBest Update
if max(fitnessValue) > gBest_fitness
    found = find(fitnessValue == max(fitnessValue));
    found = found(1);
    gBest_fitness = max(fitnessValue);
    gBest_particle = population(found, :);    
end

fprintf('Initialization gBest = %d\n', gBest_fitness);

for iteration=1:max_iteration
    fprintf('\nIteration %d/%d\n', iteration, max_iteration);

    % Update velocity
    W = 0.6;
    c1 = 1.2;
    c2 = 1.2;
    r1 = rand();
    r2 = rand();
    for i=1:nParticles
        particleDec = int64(binToDec(population(i, :)));
        velocity(i, 1) = W * velocity(i, 1) + c1 * r1 * (binToDec(pBest_particle(i, :)) - particleDec) + c2 * r2 * (binToDec(gBest_particle) - particleDec);
        popDec = abs(int64(particleDec + velocity(i, 1)));
        popBin = decToBin(popDec);
        %if the total bits lower than nFeatures + nBits
        if size(popBin, 2) < (nFeatures + nBits)
            popBin = [zeros(1, (nFeatures + nBits)-size(popBin, 2)) popBin];
        end
        %if the number of hidden node is more than the number of samples
        if binToDec(popBin(1, nFeatures+1:end)) > size(trainingData, 1)
            popBin(1, nFeatures+1:end) = decToBin(size(trainingData, 1));
        end
        population(i, :) = popBin;
    end
    
    
    %ELM train for fitness function
    fprintf('%8s %15s %15s %15s %15s %15s %15s\n', 'Particle', 'nHiddenNode', 'pBest', 'Time', 'TrainAcc', 'TestAcc', 'SelectedFeatures');
    for i=1:nParticles
        tic;
        fprintf('%8d %15d ', i, binToDec(population(i, nFeatures+1:end)));
        % TRAINING
        maskedTrainingFeature = featureMasking(trainingData, population(i, 1:nFeatures));% prepare the feature data (masking)
        trainingTarget = full(ind2vec(trainingData(:,end)'))';% prepare the target data (transformation from 4 into [0 0 0 1 0 0])
        elmModel = trainELM(binToDec(population(i, nFeatures+1:end)), maskedTrainingFeature, trainingTarget);

        % TESTING
        maskedTestingFeature = featureMasking(testingData, population(i, 1:nFeatures));% prepare the feature data (masking)
        testingTarget = full(ind2vec(testingData(:,end)'))';% prepare the target data (transformation from 4 into [0 0 0 1 0 0])
        elmModel = testELM(elmModel, maskedTestingFeature, testingTarget);
        fitnessValue(i, 1) = fitness(0.95, 0.05, elmModel.testingAccuracy, population(i, 1:nFeatures));

        % pBest Update
        if fitnessValue(i, 1) > pBest_fitness(i, 1)
            pBest_fitness(i, 1) = fitnessValue(i, 1);
            pBest_particle(i, :) = population(i, :);
        end
        endTime = toc;
        
        fprintf('%15d %15d %15d %15d %4s', pBest_fitness(i, 1), endTime, elmModel.trainingAccuracy, elmModel.testingAccuracy, ' ');
        f = find(population(i, 1:nFeatures)==1);
        for l=1:size(f, 2)
            fprintf('%d ', f(1, l));
        end
        fprintf('\n');        
        
    end

    % gBest Update
    if max(fitnessValue) > gBest_fitness
        found = find(fitnessValue == max(fitnessValue));
        found = found(1);
        gBest_fitness = max(fitnessValue);
        gBest_particle = population(found, :);    
    end
    fprintf('Iteration %d gBest = %d\n', iteration, gBest_fitness);
end

beep