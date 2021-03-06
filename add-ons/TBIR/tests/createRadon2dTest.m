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
function tests = createRadon2dTest
    tests = functiontests(localfunctions);
end

function operatorTest(testCase)

% Set up test image and projection angles.
x = phantom('Modified Shepp-Logan', 128);
m = size(x);
theta = 0:10:179;

% Create operators.
[K, Kadj, cleanup, ndet] = createRadon2d(m, theta, 1);
verifyEqual(testCase, ndet, 1.5 * m(1));

% Apply operator and check size.
y = K(x(:));
verifyEqual(testCase, size(y), [length(theta), 1.5 * m(1)]);

% Apply adjoint and check size.
xrecon = Kadj(y);
verifyEqual(testCase, size(xrecon), size(x(:)));

% Free resources.
cleanup();

end

function adjointnessTest(testCase)

% Set up random test data.
x = rand(128, 128);
m = size(x);
theta = 0:10:179;
y = rand(length(theta), 1.5 * m(1));

% Create operators.
[K, Kadj, cleanup, ndet] = createRadon2d(m, theta, 1);
verifyEqual(testCase, ndet, 1.5 * m(1));

% Verify adjointness.
Kx = K(x(:));
Kadjy = Kadj(y);
verifyEqual(testCase, abs(Kx(:)'*y(:) - x(:)'*Kadjy), 0, 'AbsTol', 1e-3);

% Free resources.
cleanup();

end
