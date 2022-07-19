clear all; close all; clc; % 'clear all' must be used since persistent variables might have been used in a previous run
fprintf('--------------------------------<strong>ANALYSIS IN PROGRESS</strong>----------------------------------\n')
addpath background
addpath background\CrossSectionData
addpath background\utils

global beam
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% USER INPUTS %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% MODEL DETAILS:
beam = create_beam('beam_data_test.xlsx'); % Creation of beam data 
model = 'BOTH'; % Options: 'FOM' for full-order model, 'ROM' for reduced order model by truncation method or 'BOTH' for both models analysis in a single run
DoF = {'OutBend'}; % Options: 'InBend': in-plane bending; 'OutBend': out-of-plane bending; 'Axial': axial deformation; 'Torsion': torsion
gravity = 'GravityOn'; % Options: 'GravityOn' to consider gravitational force or 'GravityOff' to disconsider it.
tspan = 0:0.1:30; % Period of simulation [s]

% INITIAL CONDITIONS:
IC = 'random'; % Options: 'random', 'equilibrium' or [p_1;p_2;...;p_n_DoF;q_1;q_2;...;q_n_DoF] for custom IC 
p0_max = 0; % Amplitude of gen. momentum's interval (used only if IC='random')
q0_max = pi; % amplitude of gen. coordinate's interval (used only if IC='random')

% ROM SETTINGS:
n_modes = 1; % Number of modes used to produce a ROM using truncation method

% ANIMATION SETTINGS:
animate = 'Y'; % Options: 'Y' or 'N'
element = '3D'; % Options: '1D' for unidimensional elements or '3D' for 3-dimensional elements
animation_file = 'sim_test'; % Filename for the simulation [str]
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Initializing Matrices:
n_DoF = length(DoF)*sum(cat(1,beam.n_element));
[M,I] = mass_matrix(DoF);
K = stiffness_matrix(DoF);
C = damping_matrix(DoF,K,0);
K(1,1) = 0;
C(1,1) = 0;
%C(1,1)=1e-1*C(1,1);

%% Equilibrium Solution:
if any(strcmp(IC,'equilibrium')) || any(strcmp(model,'ROM')) || any(strcmp(model,'BOTH'))
    x0 = zeros(n_DoF,1);
    Xeq = solve_equilibrium(K,DoF,gravity,model,x0,'PlotEq',element);
end

if any(strcmp(IC,'equilibrium'))
    X0 = [zeros(n_DoF,1),Xeq];
elseif any(strcmp(IC,'random'))
    p0 = p0_max*(2*rand(n_DoF,1)-1);
    q0 = q0_max*(2*rand(n_DoF,1)-1);
    X0 = [p0;q0];
elseif isnumeric(IC) && length(IC) == 2*n_DoF
    X0 = IC;
else
    error('IC must be "random", "equilibrium" or length 2*n_DoF if array!')
end

%% FOM Simulation:
if any(strcmp(model,'FOM')) || any(strcmp(model,'BOTH'))
    [X,Xdot] = simulation(beam,model,DoF,gravity,tspan,M,I,K,C,X0,'PlotProgress');
    p_FOM = X(:,1:n_DoF);
    q_FOM = X(:,n_DoF+1:end);

    % Hamiltonian:
    H = zeros(length(tspan),1);
    for i = 1:length(tspan)
        J = complexstep(@(q) element_positionCM(q,DoF),q_FOM(i,:));
        [~,~,~,Ug] = generalized_force(tspan(i),q_FOM(i,:),J,DoF,gravity);
        H(i) = 0.5*(p_FOM(i,:)*((J.'*M*J + I)\p_FOM(i,:).') + q_FOM(i,:)*(K*q_FOM(i,:).')) + sum(Ug);
    end

    % Simulation Results Animation:
    if any(strcmp(model,'FOM')) && any(strcmp(animate,'Y'))
        animation(tspan,q_FOM,H,DoF,element,[animation_file,'_FOM'],'gif','avi')
    end
end

%% ROM Simulation - Truncation Method
if any(strcmp(model,'ROM')) || any(strcmp(model,'BOTH'))
    
    % Initialization of the reduced order model:
    phi_r = create_rom(n_modes,DoF,M,I,K,Xeq);

    % Initial conditions:
    if (any(strcmp(IC,'equilibrium')) && ~any(strcmp(model,'BOTH'))) || ((any(strcmp(IC,'equilibrium'))) && any(strcmp(model,'BOTH')))
        eta0 = phi_r\Xeq;
        eta_eq = solve_equilibrium(K,DoF,gravity,model,eta0,phi_r,Xeq,'PlotEq',element);
        X0 = [zeros(n_modes,1),eta_eq];
    elseif any(strcmp(IC,'random')) && ~any(strcmp(model,'BOTH'))
        eta_p0 = phi_r\(p0_max*(2*rand(n_DoF,1)-1));
        eta_q0 = phi_r\(q0_max*(2*rand(n_DoF,1)-1));
        X0 = [eta_p0;eta_q0];
    elseif isnumeric(IC) && length(IC) == 2*n_modes && ~any(strcmp(model,'BOTH'))
        X0 = IC;
    elseif any(strcmp(model,'BOTH')) && ~any(strcmp(IC,'equilibrium'))
        %J0 = complexstep(@(q) element_positionCM(q,DoF),X0(n_DoF+1:end));
        %qdot0 = (J0.'*M*J0 + I)\X0(1:n_DoF);
        eta_p0 = phi_r\X0(1:n_DoF);
        eta_q0 = phi_r\X0(n_DoF+1:end);
        X0 = [eta_p0;eta_q0];
    else
        error('IC_ROM must be "random", "equilibrium" or length 2*n_modes if array!')
    end

    % Reduced-order model dynamics simulation:
    [X_ROM,Xdot_ROM] = simulation(beam,model,DoF,gravity,tspan,M,I,K,C,X0,phi_r);
    p_ROM = (phi_r*X_ROM(:,1:n_modes).').';
    q_ROM = (phi_r*X_ROM(:,n_modes+1:end).').';

    % Hamiltonian:
    H_ROM = zeros(length(tspan),1);
    for i = 1:length(tspan)
        J = complexstep(@(q) element_positionCM(q,DoF),q_ROM(i,:));
        [~,~,~,Ug] = generalized_force(tspan(i),q_ROM(i,:),J,DoF,gravity);
        H_ROM(i) = 0.5*(X_ROM(i,1:n_modes)*((phi_r.'*J.'*M*J*phi_r + phi_r.'*I*phi_r)\X_ROM(i,1:n_modes).') + q_ROM(i,:)*(K*q_ROM(i,:).')) + sum(Ug);
    end

    % Create animation of the ROM dynamics solution:
    if any(strcmp(model,'ROM')) && any(strcmp(animate,'Y'))
        animation(tspan,q_ROM,H_ROM,DoF,element,[animation_file,'_ROM'],'gif','avi')
    elseif any(strcmp(model,'BOTH')) && any(strcmp(animate,'Y'))
        animation(tspan,q_FOM,H,DoF,element,[animation_file,'_BOTH'],'gif','avi',q_ROM,H_ROM)
    end
end
fprintf('-----------------------------------<strong>END OF ANALYSIS</strong>------------------------------------\n')