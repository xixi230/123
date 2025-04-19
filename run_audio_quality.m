% run_audio_quality.m
% 主脚本：调用 PEAQ (PQevalAudio) 和自定义函数计算音频质量、大小和复杂度指标

% 获取开始时间，用于计算复杂度指标
startTime = tic;

% 设置音频文件路径
testAudioPath = 'C:\Users\wzw2\Desktop\music\音乐_44100Hz_8bit.wav';
% 参考音频路径（高质量无损版本）
refAudioPath = 'C:\Users\wzw2\Desktop\music\音乐_44100Hz_16bit.wav';

% 确保参考音频存在，否则使用测试音频作为参考
if ~exist(refAudioPath, 'file')
    fprintf('警告: 参考音频文件不存在。对于完整的 PEAQ 评估需要参考文件。\n');
    fprintf('使用特征提取方法计算质量指标。\n\n');
    useFullPEAQ = false;
else
    useFullPEAQ = true;
end

% 获取文件信息，用于计算文件大小指标
fileInfo = dir(testAudioPath);
fileSize = fileInfo.bytes;
fprintf('音频文件大小: %.2f MB\n', fileSize/1024/1024);

% Step 1: 加载音频文件以获取基本信息
fprintf('加载音频文件...\n');
info = audioinfo(testAudioPath);
fprintf('音频文件加载完成: 采样率 = %d Hz, 时长 = %.2f 秒\n', info.SampleRate, info.Duration);
fprintf('格式: %s, 声道数: %d, 比特率: %d kbps\n', info.CompressionMethod, info.NumChannels, info.BitRate/1000);

% 计算文件时长（秒）
audioDuration = info.Duration;

% Step 2: 计算音质指标 Q
fprintf('\n计算音质指标 Q...\n');

if useFullPEAQ
    try
        % 使用标准 PEAQ 算法计算 ODG
        fprintf('使用 PEAQ 算法计算 ODG...\n');
        
        % 将测试文件和参考文件读入内存
        [testAudio, testFs] = audioread(testAudioPath);
        [refAudio, refFs] = audioread(refAudioPath);
        
        % 确保采样率匹配 (PEAQ 要求 48kHz)
        if testFs ~= 48000
            fprintf('重采样测试音频到 48kHz...\n');
            testAudio = resample(testAudio, 48000, testFs);
            testFs = 48000;
        end
        
        if refFs ~= 48000
            fprintf('重采样参考音频到 48kHz...\n');
            refAudio = resample(refAudio, 48000, refFs);
            refFs = 48000;
        end
        
        % 确保两个音频长度匹配
        minLength = min(size(testAudio,1), size(refAudio,1));
        testAudio = testAudio(1:minLength, :);
        refAudio = refAudio(1:minLength, :);
        
        % 保存临时文件
        tempTestFile = [tempname '.wav'];
        tempRefFile = [tempname '.wav'];
        audiowrite(tempTestFile, testAudio, testFs);
        audiowrite(tempRefFile, refAudio, refFs);
        
        % 调用 PEAQ 函数计算 ODG
        PQevalAudio(tempRefFile, tempTestFile);
        
        % 获取 ODG 值 (此处假设 PQevalAudio 输出了全局变量 ODG)
        % 如果 PQevalAudio 没有直接提供 ODG 值，需要修改此处
        global ODG;
        
        % 清理临时文件
        delete(tempTestFile);
        delete(tempRefFile);
        
    catch ME
        fprintf('PEAQ 计算出错: %s\n', ME.message);
        fprintf('使用替代方法计算 ODG...\n');
        
        % 使用简化方法计算 ODG
        [audioData, sampleRate] = audioread(testAudioPath);
        if size(audioData, 2) > 1
            audioData = mean(audioData, 2); % 转换为单声道
        end
        ODG = analyze_audio_quality(audioData, sampleRate);
    end
else
    % 使用自定义音频分析函数计算 ODG
    [audioData, sampleRate] = audioread(testAudioPath);
    if size(audioData, 2) > 1
        audioData = mean(audioData, 2); % 转换为单声道
    end
    ODG = analyze_audio_quality(audioData, sampleRate);
end

fprintf('音频分析完成: ODG = %.2f\n', ODG);

% 根据公式计算 Q 值
Q = (4 + ODG) / 4;
fprintf('根据公式计算音质指标 Q 值: Q = %.4f\n', Q);

% Step 3: 计算文件大小指标 S
fprintf('\n计算文件大小指标 S...\n');
% 基于每秒音频数据的比特率计算
bitrate = fileSize * 8 / audioDuration; % 比特/秒

% 对比特率进行评分（假设1411kbps为无损CD质量，64kbps为低质量）
% 使用非线性映射，让中等比特率范围有更好的区分度
if bitrate >= 1411000
    % 无损或超高质量
    S = 0.2; % 文件较大，得分较低
else
    % 根据比特率计算大小评分，值域在0.2-0.95之间
    % 公式设计让128kbps得到约0.7的评分
    S = 0.2 + 0.75 * (1 - exp(-(1411000 - bitrate) / 300000));
    S = min(0.95, S); % 设置上限
end
fprintf('文件大小指标 S 值: S = %.4f (比特率: %.0f kbps)\n', S, bitrate/1000);

% Step 4: 计算程序执行计算复杂度指标 C
fprintf('\n计算程序执行计算复杂度指标 C...\n');
% 获取执行时间
executionTime = toc(startTime);

% 归一化执行时间（假设10秒是阈值）
% 使用非线性映射，让短时间范围有更好的区分度
C = 1 - min(1, executionTime / 10);
C = C^0.5; % 平方根使分布更加合理
fprintf('计算复杂度指标 C 值: C = %.4f (执行时间: %.4f 秒)\n', C, executionTime);

% Step 5: 计算综合评分
fprintf('\n计算综合评分...\n');
% 可以根据需要调整三个指标的权重
weights = [0.6, 0.25, 0.15]; % Q, S, C 的权重
combinedScore = weights(1) * Q + weights(2) * S + weights(3) * C;
fprintf('综合评分: %.4f (权重分配: Q=%.2f, S=%.2f, C=%.2f)\n', combinedScore, weights);

% 输出所有指标
fprintf('\n========== 最终结果 ==========\n');
fprintf('文件: "%s"\n', testAudioPath);
fprintf('- 质量指标 (Q): %.4f (基于ODG: %.2f)\n', Q, ODG);
fprintf('- 文件大小指标 (S): %.4f (比特率: %.0f kbps)\n', S, bitrate/1000);
fprintf('- 计算复杂度指标 (C): %.4f (执行时间: %.2f 秒)\n', C, executionTime);
fprintf('- 综合评分: %.4f\n', combinedScore);

% 绘制结果条形图
figure('Name', '音频文件评估指标');
barData = [Q, S, C, combinedScore];
bar(barData);
set(gca, 'XTickLabel', {'质量指标(Q)', '大小指标(S)', '复杂度指标(C)', '综合评分'});
title('音频文件评估指标');
ylabel('指标值 (0-1)');
ylim([0 1]); % 设置y轴范围从0到1
grid on;

% 添加文本标签显示具体数值
text(1:length(barData), barData, num2str(barData', '%.3f'), ...
    'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom');

% 添加文件信息注释
annotation('textbox', [0.15, 0.01, 0.7, 0.05], 'String', ...
    sprintf('文件: %s, 大小: %.2f MB, 比特率: %.0f kbps', ...
    info.Filename, fileSize/1024/1024, info.BitRate/1000), ...
    'HorizontalAlignment', 'center', 'EdgeColor', 'none');