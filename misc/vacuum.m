function deleted = vacuum
% cleans up all the zero byte files in the current folder
files = dir;
deleted = {};
j = 0;
for i = 1:length(files)
    if not(files(i).isdir)
        if files(i).bytes == 0
            delete(files(i).name)
            j = j + 1;
            deleted{j} = files(i).name;
        end
    end
end
fprintf('Deleted %i files: %s', j, strjoin(deleted, ', '));
end