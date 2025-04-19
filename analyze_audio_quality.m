function odg = analyze_audio_quality(audioData, sampleRate)
    % 此函数分析音频特性并计算ODG值
    % 参数:
    % audioData (array): 音频样本数据
    % sampleRate (int): 采样率
    % 返回:
    % odg (float): 计算得到的ODG值，范围-4到0
    
    % 1. 信噪比计算优化
    % 使用更复杂的信号/噪声分离方法
    [waveEnv, ~] = envelope(audioData, 100, 'peak');
    thresholdLevel = median(waveEnv) * 1.5;
    signalMask = waveEnv > thresholdLevel;
    signalPart = audioData(signalMask);
    noisePart = audioData(~signalMask);
    
    % 避免空数组
    if isempty(signalPart)
        signalPart = audioData;
        noisePart = zeros(size(audioData)/10);
    end
    
    signalPower = mean(signalPart.^2);
    noisePower = mean(noisePart.^2) + eps;
    
    snrEstimate = 10 * log10(signalPower / noisePower);
    
    % SNR范围调整，使用非线性映射增强差异
    snrNorm = tanh(snrEstimate/30) * 0.5 + 0.5; % 将SNR映射到0-1之间，强调中间差异
    
    % 2. 频率域分析增强
    nfft = min(2^nextpow2(length(audioData)), 8192); % 自适应FFT长度
    
    % 计算频谱
    [S, F] = pwelch(audioData, hamming(nfft), round(nfft/2), nfft, sampleRate);
    
    % 将频谱分为多个频带进行分析
    bandEdges = [20, 250, 1000, 4000, 16000];
    bandMetrics = zeros(length(bandEdges)-1, 1);
    
    for b = 1:length(bandEdges)-1
        bandIndices = (F >= bandEdges(b) & F < bandEdges(b+1));
        if any(bandIndices)
            bandS = S(bandIndices);
            % 计算频带平坦度
            bandFlatness = geomean(bandS) / (mean(bandS) + eps);
            % 计算频带能量比
            bandEnergy = sum(bandS) / (sum(S) + eps);
            % 综合评分
            bandMetrics(b) = bandFlatness * bandEnergy;
        end
    end
    
    % 各频带加权平均
    bandWeights = [0.1, 0.3, 0.4, 0.2]; % 中频段权重较高
    spectralBalance = sum(bandMetrics .* bandWeights');
    
    % 3. 瞬态分析 - 检测音频中的瞬态变化
    diffAudio = diff([0; audioData]); % 计算样本间差异
    normalizedDiff = diffAudio / (max(abs(diffAudio)) + eps);
    transientDensity = sum(abs(normalizedDiff) > 0.1) / length(audioData);
    
    % 4. 谐波分析
    % 计算谐波和非谐波比例
    windowSize = round(0.05 * sampleRate); % 50ms窗口
    step = round(0.025 * sampleRate); % 25ms步进
    
    harmonicRatio = 0;
    numWindows = 0;
    
    % 限制分析窗口数量，避免过长音频导致过多计算
    maxWindows = min(100, floor((length(audioData)-windowSize)/step));
    windowIndices = round(linspace(1, length(audioData)-windowSize, maxWindows));
    
    for i = windowIndices
        frame = audioData(i:i+windowSize-1);
        frame = frame .* hamming(windowSize);
        
        % 自相关分析检测谐波结构
        [acf, lags] = xcorr(frame, 'coeff');
        acf = acf(lags >= 0);
        
        % 排除零延迟
        acf = acf(2:end);
        
        % 找出自相关峰值
        [peaks, ~] = findpeaks(acf);
        if ~isempty(peaks)
            harmonicRatio = harmonicRatio + max(peaks);
            numWindows = numWindows + 1;
        end
    end
    
    % 避免除零
    if numWindows > 0
        harmonicRatio = harmonicRatio / numWindows;
    end
    
    % 5. 动态范围分析增强
    % 使用振幅直方图分析
    histBins = linspace(-1, 1, 100);
    [counts, ~] = histcounts(audioData, histBins);
    normalizedCounts = counts / sum(counts);
    
    % 计算熵作为动态分布指标
    validIndices = normalizedCounts > 0;
    entropy = -sum(normalizedCounts(validIndices) .* log2(normalizedCounts(validIndices)));
    entropyNorm = entropy / log2(length(histBins) - 1); % 归一化到0-1
    
    % 6. 削波失真分析
    upperThreshold = 0.95;
    lowerThreshold = 0.20;
    
    upperClip = sum(abs(audioData) > upperThreshold) / length(audioData);
    lowerActivity = sum(abs(audioData) > lowerThreshold) / length(audioData);
    
    % 削波比与活动比的平衡
    clippingFactor = upperClip / (lowerActivity + eps);
    
    % 综合所有指标计算ODG
    % 权重可调整以适应不同类型音频
    weights = [0.25, 0.20, 0.15, 0.15, 0.15, 0.10];
    
    % 计算各因素贡献
    factors = [
        snrNorm * 4 - 2,                       % SNR贡献，范围-2到2
        (spectralBalance * 4 - 2),             % 频谱贡献，范围-2到2
        (transientDensity * 6 - 2),            % 瞬态贡献，范围-2到4
        (harmonicRatio * 4 - 2),               % 谐波贡献，范围-2到2
        (entropyNorm * 4 - 2),                 % 动态贡献，范围-2到2
        max(-4, min(0, -clippingFactor * 8))   % 削波贡献，范围-4到0
    ];
    
    % 输出各因素贡献值以便调试
    fprintf('分析因素: SNR=%.2f, 频谱=%.2f, 瞬态=%.2f, 谐波=%.2f, 动态=%.2f, 削波=%.2f\n', factors);
    
    % 综合计算ODG
    odg = sum(factors .* weights');
    
    % 限制ODG范围在-4到0之间
    odg = max(-4, min(0, odg));
    
    % 输出原始ODG值以便调试
    fprintf('原始ODG计算值: %.4f, 限制后: %.4f\n', sum(factors .* weights'), odg);
end