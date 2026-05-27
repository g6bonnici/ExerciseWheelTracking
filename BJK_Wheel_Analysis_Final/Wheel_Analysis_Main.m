clear
exp = 'CD169_Ex_new_cohort';             % Define experiment / folder for results
gp = '10_21_to_present';                      % Define analysis group
missingVal = 0.1;              % Use a decimal value!!! This is used for when receiver outputs missing values for correction in analysis
startDate = datetime('21-Oct-2025 20:00:00', 'InputFormat', 'dd-MMM-yyyy HH:mm:ss'); %start date - start time of active period
endDate = datetime('23-Mar-2026 19:59:00', 'InputFormat', 'dd-MMM-yyyy HH:mm:ss'); %end date - end time of inactive period

wheelRadius = 6.0198;           %Wheel radius in cm

addpath('Wheel_Files')           % Add your wheel file .CSV to Wheel_Files, this adds these to the code. NEEDS TO BE .CSV
warning off

%% Auto-detect operating system

if ispc
    separator = '\'; % For pc operating systems
else
    separator = '/'; % For unix (mac, linux) operating systems
end

mkdir(strcat(pwd,separator,'Wheel_Analysis_Final',separator,exp,separator,gp,separator));  %Making folder
Folder = strcat(pwd,separator,'Wheel_Analysis_Final',separator, exp,...
    separator, gp, separator);

%% Load all the csv tracking files across wheel files
disp('Step 1: Load data');
dirName = strcat(pwd,separator,'Wheel_Files',separator);
wheels = dir([dirName, '*.csv']);

%% Data processing and sorting
disp('Step 2: Process data');
% Load csvs and process in data structure
analysis_data_raw = cell([size(wheels,1) 5]);                %This is where all raw and analyzed data will be stored
g = struct;

for w = 1:size(wheels,1)                                 % Completes the data set up for all 'mice' (csvs)
    disp(wheels(w).name);
    [~,wheel_num,~] = fileparts(wheels(w).name);
    destfile = strcat(fullfile(Folder, wheel_num),separator);
    mkdir(destfile);
    g.Temp = readcell(wheels(w).name);     %Place data in structure
   
    g.Headers = g.Temp(1,:);                           %Adds first row "headers" into analysis data
    analysis_data_raw(w,1)={g.Headers};                     

     if(w>1)
         if ~isequal(analysis_data_raw{w-1,1}(1,:),analysis_data_raw{w,1}(1,:))   % Ensures first row labeled correctly for data analysis   
             error('Mice missing in data/not all in same order');
         end
     end

     g.Temp = g.Temp(2:end,:);                          %Deletes first row now since we verified labeling
     analysis_data_raw(w,2)={g.Temp(:,1)};                   %Saves dates
     analysis_data_raw(w,3)={g.Temp(:,2:end)};               %Saves wheel per mouse
     analysis_data_raw(w,4) =  analysis_data_raw{w,2}(1,:);  %Saves first day
     analysis_data_raw(w,5) =  analysis_data_raw{w,2}(end,:); %Saves Last day


end

dateArray = vertcat(analysis_data_raw {:,4});                    %Converts cell to array to get dates properly sorted

[~, sortIdx] = sort(dateArray);                                   % Get sorting indices based on start times

analysis_data_raw = analysis_data_raw(sortIdx, :);                 % Apply sorting to the entire cell array

tempDate = vertcat(analysis_data_raw{:,2});                    %Stores all date/times together


tempWheel= vertcat(analysis_data_raw {:,3});                  %Stores all mice revolutions by row

tempWheel(cellfun(@ismissing, tempWheel)) = {missingVal};  %replaces missing values with the decimal value above. Make sure no NaNs in files or else will error

finalWheel= cell2mat(tempWheel);

dateFinal = vertcat(tempDate{:});
dateFinal = dateshift(dateFinal, 'start', 'minute');

%% 

% Analysis

dayStart = find(timeofday(dateFinal) == hours(20));

%Initialize storage for valid periods
finalDays = [];
goodDay=0;

%Check if each period is exactly 24 hours
for i = 1:length(dayStart)-1
    startIdx = dayStart(i);
    endIdx = dayStart(i+1) - 1; % The last index before the next 20:00

    timeDiff = hours(dateFinal(endIdx) - dateFinal(startIdx));

    activeEnd = dateFinal(startIdx) + hours(10);
    activeEndIdx = dayStart(i) + 600;



    if dateFinal(startIdx) < endDate

        %Check if the time difference is ~ 24 hours
        if (timeDiff >= 23 && timeDiff <= 25)

            if dateFinal(activeEndIdx) == activeEnd

                goodDay = goodDay + 1;

                for w = 1:size(finalWheel,2)  

                    activeMissing = 600 - sum(finalWheel(startIdx:activeEndIdx, w) == 0.1);

                            if activeMissing <= 120   %to prevent divide by zero error
                                activeMissing = 600;
                            end

                    activeMissingWheels (goodDay,w)  =  activeMissing / 600;

                    sleepMissing = (endIdx- activeEndIdx) - sum(finalWheel(activeEndIdx:endIdx, w) == 0.1);
                    
                    if sleepMissing <= 60   %to prevent divide by zero error
                       
                        sleepMissing = (endIdx- activeEndIdx) ;
                     
                    end

                    sleepMissingWheels (goodDay,w)  =  sleepMissing / (endIdx- activeEndIdx);

                end      
                
                finalDays = [finalDays; startIdx, activeEndIdx, endIdx]; % Store only valid periods
            
            end       
        end
    end
end


finalWheel(finalWheel == missingVal) = 0;
finalTurns = [];

for k = 1: size(finalDays,1)
    
    normActiveWheel = sum(finalWheel(finalDays(k,1):finalDays(k,2),:),1) ./ activeMissingWheels (k,:); %normalizing active for missing
    
    normSleepWheel = sum(finalWheel(finalDays(k,2):finalDays(k,3),:),1) ./ sleepMissingWheels (k,:);  %normalizing inactive for missing
   
    finalTurns = [finalTurns; (normActiveWheel  + normSleepWheel)];   %combines the normalized values for "final # of wheel turns"
    
end
%%
% Final Calcs
disp('Step 3: Final calculations');

daysFromStart = days(dateFinal(finalDays(:,3))-startDate);       %Gets days from start of first wheel running 

%Compute week numbers
weekNumbers = floor((daysFromStart + 1) / 7) + 1;

uniqueWeeks = unique(weekNumbers);

weeklyAverage = zeros(length(uniqueWeeks),size(finalTurns,2));

for w = 1:length(uniqueWeeks)
   for m = 1:size(finalTurns,2)

        idx = weekNumbers == uniqueWeeks(w);  % Find indices for this week
       
        weekValues = finalTurns(idx,m);  % Extract values for this week

        numDays = nnz(weekValues);  % Count recorded days, excluding days with 0 activity. Useful for bad recording days

       if numDays == 0
           weeklyAverage (w,m) = 0;  %if no good days then no value calculated. useful for if wheels are not recording well for a week
       else
          weeklyAverage (w,m) =  sum(weekValues) / (numDays);  % Average turns over available days
       end
   end
end

turnToKm = (2* 6.0198* pi * weeklyAverage)/100000;                  %Convers # turns into km

disp('Step 4: Saving');
save([Folder strcat(exp, '_', gp)])     %Saves alll data in .mat format in the Analysis final folder

disp('Done :)');