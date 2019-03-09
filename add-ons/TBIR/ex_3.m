% Copyright 2019 Lukas F. Lang and Sebastian Neumayer
%
% This file is part of TBIR.
%
%    TBIR is free software: you can redistribute it and/or modify
%    it under the terms of the GNU General Public License as published by
%    the Free Software Foundation, either version 3 of the License, or
%    (at your option) any later version.
%
%    TBIR is distributed in the hope that it will be useful,
%    but WITHOUT ANY WARRANTY; without even the implied warranty of
%    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
%    GNU General Public License for more details.
%
%    You should have received a copy of the GNU General Public License
%    along with TBIR.  If not, see <http://www.gnu.org/licenses/>.
%
% This script creates the results shown in Figure 4.
% Results are saved to the folder 'results'. When run for the first time,
% measurements (sinograms) are created and also saved to the results
% folder. In every subsequent run these measurements are used again. Make
% sure to delete these files when you change the images or their sizes.
clear;
close all;
clc;

% Flag that activates plotting.
plot = false;

% Set results output folder.
outputfolder = fullfile(FAIRpath, 'add-ons', 'TBIR', 'results', 'ex_3');
mkdir(outputfolder);

% Name of dataset.
name = 'HNSP';

% Load images.
path = fullfile(FAIRpath, 'kernel', 'data');
file1 = 'HNSP-R.jpg';
file2 = 'HNSP-T.jpg';
image1 = double(imread(fullfile(path, file1)));
image2 = double(imread(fullfile(path, file2)));

% Save size of template.
m = size(image1);

% Set bumber of Runge-Kutta steps.
N = 5;

% Define data term.
dist = 'NCC_op';

% Define regularization term.
reg = {'mfCurvatureST', 'mfDiffusionST',...
       'mfCurvatureST', 'mfDiffusionST'};

% Define objective.
objfun = {'MPLDDMMobjFctn', 'MPLDDMMobjFctn',...
          'LDDMMobjFctn', 'LDDMMobjFctn'};

% Define image model.
imageModel = 'splineInterMex';

% Define temporal discretization of the velocity (number of time steps is
% then nt + 1.
nt = 1;

% Define noise level.
sigma = {0.05, 0.05,...
         0.05, 0.05};

% Set regularization parameters.
alpha = {[20, 10], [200, 10],...
         [20, 10], [200, 10]};

% Set Hessian shift.
hessianShift = 1e-2;

% Set domain size.
omega = [0, 1, 0, 1];

% Set domain for velocities by padding.
pad = 0.5;
omegaV = omega;
omegaV(1:2:end) = omegaV(1:2:end) - pad;
omegaV(2:2:end) = omega(2:2:end) + pad;

% Initialize models.
imgModel('reset', 'imgModel', imageModel);
trafo('reset', 'trafo', 'affine2D');
distance('reset', 'distance', dist);
viewImage('reset', 'viewImage', 'viewImage2D', 'colormap', gray(256));
NPIRpara = optPara('NPIR-GN');
NPIRpara.maxIter = 30;
NPIRpara.scheme = @GaussNewtonLDDMM;

% Create multilevel versions of template.
[ML, minLevel, maxLevel, ~] = getMultilevel(image1, omega, m, 'fig', 0);

% Set directions for Radon transform.
theta = linspace(0, 180, 10);

% Set up operators for all levels.
for k=minLevel:maxLevel
    [ML{k}.K, ML{k}.Kadj, ML{k}.cleanup, ML{k}.ndet] = createRadon2d(size(ML{k}.T), theta);
end

% Run algorithm for each setting.
mV = @(m) ceil(1*m);
rec = cell(length(alpha), 1);
for k=1:length(alpha)
    % Check if measurements exists, otherwise create.
    sinogramfile = fullfile(outputfolder, 'Sinograms', sprintf('%s_sino_%g.mat', name, sigma{k}));
    if(exist(sinogramfile, 'file'))
        S = load(sinogramfile);
        ML{maxLevel}.R = S.R;
    else
        % Apply operator on finest level to generate synthetic measurements.
        R = ML{maxLevel}.K(image2);
        ML{maxLevel}.R = R;

        % Add noise to measurements.
        ML{maxLevel}.R = addnoise(ML{maxLevel}.R, sigma{k});
        
        % Save measurements.
        mkdir(fullfile(outputfolder, 'Sinograms'));
        save(sinogramfile, 'R', 'theta', 'm');
    end

    % Save template, unknown image, and measurements to results folder.
    imwrite(image1 / 255, fullfile(outputfolder, sprintf('%s_source.png', name)));
    imwrite(image2 / 255, fullfile(outputfolder, sprintf('%s_target.png', name)));
    Rsize = size(ML{maxLevel}.R, 2);
    Rsq = imresize(ML{maxLevel}.R, [Rsize, Rsize], 'nearest');
    imwrite(Rsq / max(Rsq(:)), fullfile(outputfolder, sprintf('%s_sino.png', name)));
    
    % Create multilevel versions of measurements.
    ML = multilevelRadon2d(ML, maxLevel, minLevel);

    % Run indirect registration.
    regularizer('reset', 'regularizer', reg{k}, 'nt', nt,...
        'alpha', alpha{k}, 'HessianShift', hessianShift);
    [vc, ~, ~, his] = MLLDDMM(ML, 'operator', true, 'minLevel',...
        minLevel, 'maxLevel', maxLevel, 'omegaV', omegaV, 'mV', mV,...
        'N', N, 'parametric', false, 'NPIRpara', NPIRpara,...
        'NPIRobj', str2func(objfun{k}), 'plots', plot);

    % Transform template and reshape.
    yc = getTrafoFromInstationaryVelocityRK4(vc, getNodalGrid(omega,m),...
        'omega', omegaV, 'm', m, 'nt', nt, 'tspan', [1, 0], 'N', N);
    rec{k} = linearInterMex(ML{maxLevel}.T, omega, center(yc, m));
    rec{k} = reshape(rec{k}, m);
    
    % Output stats.
    fprintf('Elapsed time is: %.2f seconds, SSIM=%.3f.\n', his.time, ssim(rec{k}, image2));
    
    % Save result.
    [resfile, paramfile] = saveresults(name, outputfolder, image1, image2,...
        ML{maxLevel}.R, rec{k}, dist, reg{k}, objfun{k}, imageModel, N, nt,...
        alpha{k}, theta, sigma{k}, his.time);
end

% Free resources.
for k=minLevel:maxLevel
    ML{k}.cleanup();
end
close all;

% Plot result.
if(plot)
    figure;
    colormap gray;
    figure;
    colormap gray;
    subplot(3, 3, 1);
    imagesc(image1, [0, 255]);
    axis image;
    title('Template image');
    subplot(3, 3, 2);
    imagesc(image2, [0, 255]);
    axis image;
    title('Unknown image');
    subplot(3, 3, 3);
    imagesc(ML{maxLevel}.K(image2));
    axis square;
    title('Measurements');
    ylabel('Directions');
    for k=1:length(alpha)
        subplot(3, 3, 4 + k);
        imagesc(rec{k}, [0, 255]);
        axis image;
    end
end