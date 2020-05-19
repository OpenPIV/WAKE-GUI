function [x_c, time, Cd_steady, Cd_unsteady] = drag_force(A, INPUTS)
% LAST UPDATE IN: 19/05/2020
% By: Hadar Ben-Gida
%
% Update 1.6
% 1. The origin of the (X,Y) coordinate system of the PIV images is set at 
%   the bottom left corner of the image, where the x-axis points right and
%   the y-axis points upwards.
% 2. The WAKE GUI is now reading .mat files that were generated by spatialbox,
%   from .vec files of either INSIGHT or OPENPIV. This is done according to
%   the value of the dy variable. dy>0 relates to OPENPIV .mat file. dy<0
%   relates to INSIGHT .mat file.
% 3. OPENPIV saves PIV images with the y-axis originated at the upper left
%   corner and pointing downwards. As a result, the v velocity component is 
%   flipped in sign. To solve this, when a .mat is loaded from OPENPIV, we
%   flipped the y-axis, and change the sign of the v velocity component and
%   the partial derivatives dv/dx and du/dx.
% 4. dy is taken positive throughout the wake and forces analyses, yet if
%   the lsgradient function is used, dy value has to be negative. This is
%   because the definition of our y-axis (positive upwards).

% Update 1.1
% Fluctuating velocities are now computed based on the averaged velocity of
% each PIV map
%
%
%% INPUTS
% A - .mat file consist with all the flow data
% INPUTS - Vector containing all the different paramters for the program 
% INPUTS = [laser_dt, p_cm, dt, chord, wingspan, body_l, body_w, weight,...
%           Uinf, density, viscosity, horizontal_cut, vertical_cut,...
%           cycle_ni, cycle_nf];
%%

%% OUTPUTS
% x_c = x/c distance corresponding to the wingbeats cycles [vector]
% time - Physical time of the wingbeats cycles [vector]
% Cd_steady - Steady 2D drag coefficient [vector]
% Cd_unsteady - Unsteady 2D drag coefficient [vector]
%%



%% METER TO PIXEL PARAMETERS 
p_cm = INPUTS(2); %[pixel/cm]
m_p = (1/p_cm)/100; %[m/pixel]
%%



%% WING PARAMETERS
c = INPUTS(4); % Bird's characteristic chord [m]
b = INPUTS(5); % Bird's wingspan [m] (includes the body width)
W = INPUTS(8); % Bird's weight [kg]
g = 9.81; % Gravitational acceleration [m/sec2]
bl = INPUTS(6); % Bird's body length [m]
bw = INPUTS(7); % Bird's body width [m]
%%



%% FLOW PARAMETERS
rho = INPUTS(10); % Air Density [kg/m3] at 14.8oC
Mu = INPUTS(11); %[Pa*sec] Air Viscosity
U_inf = INPUTS(9); % Free Stream Velocity [m/sec]
%%



%% GETTING THE FLOW QUANTITIES AND RE-DEFINE THE VELOVITY MAP SIZE
dt_laser = INPUTS(1); % [sec] Time difference between consecutive PIV images
dt = INPUTS(3); % [sec] Time difference between consecutive velocity maps
h_cut = INPUTS(12); % number of vectors we slice from the vertical edges of the PIV image
v_cut = INPUTS(13); % number of vectors we slice from the horizontal edges of the PIV image


A.x = A.x(1+v_cut:end-v_cut, 1+h_cut:end-h_cut);
x = (A.x - A.x(1,1)).*m_p;  % x Coordinate [m]

A.y = A.y(1+v_cut:end-v_cut, 1+h_cut:end-h_cut);

dx = A.dx*m_p; %dx=16pixels * (meter/pixel)
dy = A.dy*m_p; %dy=16pixels * (meter/pixel)

% THE (X,Y) ORIGIN IS SET THE LEFT BOTTOM CORNER OF THE IMAGE, WHERE X-AXIS
% IS DIRECTED TO THE RIGHT AND THE Y-AXIS IS DIRECTED UPWARDS
if dy < 0 % insight images (x,y) origin is at the left bottom corner of the image
    dy = dy*(-1);
elseif dy > 0 % openpiv images (x,y) origin is at the left upper corner of the image
    A.y = flip(A.y,1); % flipping the y axis to be origned at the left bootom corner of the image and directed upwards
    A.v = -A.v; % Flipping the v-component velocity to fit the new y-axis origin
    A.dvdx = -A.dvdx; % Flipping the dv/dx to fit the new y-axis origin
    A.dudy = -A.dudy; % Flipping the du/dy to fit the new y-axis origin
end
y = (A.y - A.y(end,1)).*m_p;  % y Coordinate [m]
y = y - (y(1)*0.5); % Placing the origin at the center of the Y-axis

% CALCULATING DERIVATIVES
[~, ~, nTime] = size(A.u);
for i=1:nTime
    [A.dudx(:,:,i), A.dudy(:,:,i)] = lsgradient(A.u(:,:,i), A.dx, -abs(A.dy)); % dy must be negative in lsgradient
    [A.dvdx(:,:,i), A.dvdy(:,:,i)] = lsgradient(A.v(:,:,i), A.dx, -abs(A.dy)); % dy must be negative in lsgradient
end
%%



%% Computing the Fluctuating velocity maps based on the spatial average
% Uncomment in order to use the uf & vf computed from the Spatial ToolBox
% [~,~,nTime] = size(A.uf);
% for i = 1:nTime
%     Uavg = mean(mean(A.u(:,:,i))); % getting the average streamwise velocity
%     Vavg = mean(mean(A.v(:,:,i))); % getting the average vertical velocity
%     A.uf(:,:,i) = A.u(:,:,i) - Uavg; % Computing the fluctuating streamwise velocity
%     A.vf(:,:,i) = A.v(:,:,i) - Vavg; % Computing the fluctuating vertical velocity
% end
Uavg = mean(A.u,3); % getting the average streamwise velocity
Vavg = mean(A.v,3); % getting the average vertical velocity
A.uf = A.u - Uavg; % Computing the fluctuating streamwise velocity
A.vf = A.v - Vavg; % Computing the fluctuating vertical velocity
%%


% Getting the different flow parameters (u, v, u', v', du/dx, du/dy,...)
A.u = A.u(1+v_cut:end-v_cut, 1+h_cut:end-h_cut, :);
u = A.u.*(m_p/dt_laser);
    
A.v = A.v(1+v_cut:end-v_cut, 1+h_cut:end-h_cut, :);
v = A.v.*(m_p/dt_laser);
    
A.uf = A.uf(1+v_cut:end-v_cut, 1+h_cut:end-h_cut, :);
uf = A.uf*(m_p/dt_laser);
    
A.vf = A.vf(1+v_cut:end-v_cut, 1+h_cut:end-h_cut, :);
vf = A.vf*(m_p/dt_laser);
    
A.dudx = A.dudx(1+v_cut:end-v_cut, 1+h_cut:end-h_cut, :);
dudx = A.dudx.*(1/dt_laser);
    
A.dvdx = A.dvdx(1+v_cut:end-v_cut, 1+h_cut:end-h_cut, :);
dvdx = A.dvdx.*(1/dt_laser);
    
A.dudy = A.dudy(1+v_cut:end-v_cut, 1+h_cut:end-h_cut, :);
dudy = A.dudy.*(1/dt_laser);
    
A.dvdy = A.dvdy(1+v_cut:end-v_cut, 1+h_cut:end-h_cut, :);
dvdy = A.dvdy.*(1/dt_laser);

[nRows, nColumns, ~] = size(uf); % Getting the NEW velocity map size
%% 



%% WINGBEAT TIME DATA
n_i = INPUTS(14); % Wingbeat start at this image
n_f = INPUTS(15); % Wingbeat ends at this image
nTime = n_f - n_i + 1; % Number of images for the wingbeat
%%



%% ESTIMATION OF DRAG
DRAG_steady = zeros(nTime,1);
DRAG_unsteady = zeros(nTime,1);
dudt = zeros(nRows, nColumns, nTime);
time = zeros(nTime,1);
x_c = zeros(nTime,1);

for j = n_i:1:n_f
    time(j-n_i+1) = (j-n_i)*dt; % physical time in [sec]
    x_c(j-n_i+1) = (j-n_i)*dt*U_inf/c;
    a = U_inf - u(:,:,j);    %[m/sec]      Streamwise velocity deficit
    % mean velocity deficit Drag force over the entire image on the semi-span
    DRAG_steady(j-n_i+1)=(mean(sum(((a).*(u(:,:,j)))*rho)))*dy; %[N/m]  
end
x_c = flipud(x_c);

for j = n_i:1:n_f
    % du/dt - Streamwise Acceleration Field
    dudt(:,:,j-n_i+1)=(u(:,:,j+1)-u(:,:,j-1))/(2*dt);    %[m/sec2]  
    DRAG_unsteady(j-n_i+1)=-sum(sum(dudt(:,:,j-n_i+1) ))*dx*dy*rho; %[N/m]
end

Cd_steady = DRAG_steady./(0.5*rho*c*U_inf^2);
Cd_unsteady = DRAG_unsteady./(0.5*rho*c*U_inf^2);
