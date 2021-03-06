%% DC ACC algorithm

% add helper path
addpath('../misc');
addpath('../formulation');
addpath('../wind');

%% initialize models

% initialize network model
dc = DC_model('case14');
dc.set_WPG_bus(9);

% initialize wind model
wind = wind_model(dc, 24, 0.2);

% 
epsilon = 5e-2;                         % violation parameter
zeta = 5*dc.N_G;                        % Helly-dimsension
beta = 1e-5;                            % confidence parameter

% determine number of scenarios to generate based on Eq (2-4)
N = ceil(2/epsilon*(zeta-1+log(1/beta)));
N = 20;

% generate scenarios
wind.dummy(N);
t_wind = 8;

% divide scenarios and initialize agents
m = 3;
assert(N >= m, 'There cannot be more agents than scenarios');
cut_index = ceil(linspace(1, N+1, m+1));

% generate random connection graph with fixed diameter
dm = 2;
G = random_graph(m, dm, 'rand');
% plot(digraph(G))
%% create and init agents
prg = progress('Initializing', m);
clear agents
for i = 1:m
    agents(i) = DC_agent(dc, wind, t_wind, cut_index(i), cut_index(i+1)-1); 
    prg.ping();
end
%% 
ngc = ones(m, 1);
t = 1;
infeasible = 0;

% while not converged and still feasible
while all(ngc < 2*dm+1) && not(infeasible) && t < 100
    prg = progress(sprintf('Iteration %i',t), m);
    
    % loop over agents
    for i = 1:m
        
        % loop over all incoming agents to agent i
        for j = find(G(:, i))';
            
            % add incoming A and J
            agents(i).build(agents(j).A{t}, agents(j).J(t), ...
                                                        agents(j).x(:,t));
            
        end
            
        % update agent
        agents(i).update();
        
        if isinf(agents(i).J(t+1))
            infeasible = 1;
            fprintf('Reached infeasibility');
            break
        end
            
        
        % check if J(t+1) is equal to J(t)
        if all_close(agents(i).J(t+1), agents(i).J(t), 1e-9)
            ngc(i) = ngc(i) + 1;
        else
            ngc(i) = 1;
        end
        
        prg.ping();
    end
    
    % update iteration number     
    t = t + 1;
end

%% Validation 

% store value for J and x for all agents
xstar = zeros(5*dc.N_G, m);
Js = zeros(t, m);
Js_acc = zeros_like(Js);
for i = 1:m
    xstar(:, i) = agents(i).x(:,t);
    Js(:, i) = [agents(i).J]';
    for it = 1:t
        Js_acc(it, i) = DC_f_obj(agents(i).x(:, it), dc, wind, t_wind);
    end
end

% compare agent solutions
all_agents_are_close = 1;
for j = 1:m-1
    for i = j+1:m
       if not( all_close(xstar(:, i), xstar(:, j), 1e-3) )
        all_agents_are_close = 0;
        fprintf('|| x_%i - x_%i || = %g\n', i, j,...
                                        norm(xstar(:,i)-xstar(:,j)));
       end 
    end
end



%% check the solution against all constraints a posteriori
x = sdpvar(5*dc.N_G, 1, 'full');
C_all = [];

for i = 1:N
        C_all = [C_all, DC_f_ineq(x, i, dc, wind, t_wind)];
end
%% check feasibility
feasible_for_all = 1;
for i = 1:m
    N_j = 4*dc.N_G + 2*dc.N_l;
    residuals = zeros(N*N_j,1);
    for j = 1:N
        offset = (j-1)*N_j;
        [~, residuals(offset+1:offset+N_j)] = ...
                        DC_f_check(xstar(:, i), i, dc, wind, t_wind);
    end
    if any(residuals < -1e-6)
        feasible_for_all = 0;
        fprintf('Min residual agent %i: \t %g\n', i, min(residuals));
        assign(x, xstar(:, i));
        check(C_all(residuals < -1e-6));
        fprintf('\n\n');
    end
end

%%
% calculate central solution
C_all = [C_all, DC_f_0(x, dc, wind, t_wind)];
Obj = DC_f_obj(x, dc, wind, t_wind);

opt = sdpsettings('verbose', 0);
optimize(C_all, Obj, opt);
xstar_centralized = value(x);
toc
%%
central_local_same = 1;
for i = 1:m
   if not( all_close(xstar(:, i), xstar_centralized, 1e-3) )
    central_local_same = 0;
    fprintf('|| x_%i - x_c || =  %g\n', i,...
                                    norm(xstar(:,i)-xstar_centralized));
   end 
end

if all_agents_are_close
    fprintf('\nAll agents are close\n');
else
    fprintf('\n(!) Not all agents are close\n');
end
if feasible_for_all
    fprintf('All solutions are feasible for all original constraints\n')
else
    fprintf('(!) Some solution is infeasible for all original constraints\n');
end
if central_local_same
    fprintf('Decentralized and centralized solution are the same\n');
else
    fprintf('(!) Central solution is different\n');
end
        
%% plot Js
figure(1)
clf
set(gcf, 'name', 'Objective values');
dock

hold on
grid on
xlabel('iteration')
ylabel('J(x*)');
title('Objective vs iterations');
plot(1:t, value(Obj)*ones(1,t), '-.', 'linewidth', 1.2);
plot(Js, 'r-', 'linewidth', 1);
plot(Js_acc, 'g-', 'linewidth', 1);
singletick
legend('Centralized', 'Agents', 'location', 'se');
%% plot disagreement
xs = zeros(5*dc.N_G, t, m);
for i = 1:m
    xs(:, :, i) = agents(i).x(:, 1:t);
end

disagreement = zeros(46,5);
zs = mean(xs, 3);
for i = 1:t
    for j = 1:m
        disagreement(i,j) = norm(xs(:,i,j)-zs(:,i));
    end
end

figure(2)
set(gcf, 'name', 'Disagreement');
clf
semilogy(disagreement)
grid on
hold on
xlabel('Iteration');
ylabel('|| x_i - z ||')
title('Disagreement over iterations DC aACC')
xlim([1 t])
singletick

%% show image of agents constraints

% enable figure
figure(3);
set(gcf, 'Name', 'Constraint exchange');

% make all params
scens = repmat(1:N, N_j, 1);
all_params = [reshape(scens, N_j*N, 1) repmat([1:N_j]', N, 1)];
height = N*N_j;

% loop over agents
for agent_id = 1:m
    
    % preallocate image
    image = zeros(height, t);
    
    % enable subfigure
    subplot(1,m,agent_id);
    
    % loop over iterations
    for iteration = 1:t
        
        % retrieve set of constraints
        A = agents(agent_id).A{iteration};
        if isempty(A)
            break;
        end
                
        % loop over pixel rows
        for row = 1:height
            
        % see where difference is 0 (identical)
            same_scen = A(:, 1) - all_params(row, 1) == 0;
            same_j = A(:, 2) - all_params(row, 2) == 0;

            % if this is on the same place, we have a match
            if any(same_scen & same_j)
                
                % set pixel to 1
                image(row, iteration) = 1;
            end

        end
        
    end

    % plot picture
    imagesc(image);
    
    % set labels etc
    xlabel('Iterations');
    ylabel('Scenario');
    ax = gca;
   
    ax.YTick = ceil(N_j/2):N_j:N*N_j;
    ax.YTickLabels = 1:N;
    ax.XTick = 1:t;
    title(sprintf('Agent %i', agent_id));
    
end
