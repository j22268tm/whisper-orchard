import os
from pydub import AudioSegment
from pydub.silence import detect_nonsilent

def split_audio(file_path, output_dir, min_len=30000, silence_thresh=None, silence_len=700):
    print(f"[Splitter] Loading {file_path}...")
    audio = AudioSegment.from_file(file_path)
    
    audio = audio.set_frame_rate(16000).set_channels(1)
    
    total_duration = len(audio)
    print(f"[Splitter] Total duration: {total_duration/1000:.1f}s")
    
    avg_dbfs = audio.dBFS
    print(f"[Splitter] Average dBFS: {avg_dbfs:.1f}")
    
    if silence_thresh is None:
        dynamic_thresh = avg_dbfs - 12
        silence_thresh = max(min(dynamic_thresh, -20), -60)
    
    print(f"[Splitter] Using silence threshold: {silence_thresh:.1f} dB")
    
    # 無音でない部分を検出
    print("[Splitter] Detecting non-silent segments...")
    nonsilent_ranges = detect_nonsilent(
        audio,
        min_silence_len=silence_len,
        silence_thresh=silence_thresh,
        seek_step=100
    )
    
    chunks = []
    
    if len(nonsilent_ranges) == 0:
        # 無音検出に失敗した場合は固定時間で分割
        print("[Splitter] No silence detected, using fixed-time splitting...")
        chunk_size = 60000  # 60秒ごとに分割
        for start in range(0, total_duration, chunk_size):
            end = min(start + chunk_size, total_duration)
            chunks.append(audio[start:end])
    else:
        # 無音区間で分割
        print(f"[Splitter] Found {len(nonsilent_ranges)} non-silent segments")
        
        # 連続する短いセグメントを結合
        merged_ranges = []
        current_start = nonsilent_ranges[0][0]
        current_end = nonsilent_ranges[0][1]
        
        for start, end in nonsilent_ranges[1:]:
            # 次のセグメントまでの間隔が3秒未満なら結合
            if start - current_end < 3000:
                current_end = end
            else:
                merged_ranges.append((current_start, current_end))
                current_start = start
                current_end = end
        
        merged_ranges.append((current_start, current_end))
        print(f"[Splitter] Merged into {len(merged_ranges)} segments")
        
        # セグメントを抽出
        for start, end in merged_ranges:
            # 前後に少し余裕を持たせる（500ms）
            chunk_start = max(0, start - 500)
            chunk_end = min(total_duration, end + 500)
            chunks.append(audio[chunk_start:chunk_end])
    
    # 短いチャンクを結合して最小長さを確保
    print(f"[Splitter] Merging short chunks (min length: {min_len/1000}s)...")
    merged_chunks = []
    current_chunk = None

    for chunk in chunks:
        if current_chunk is None:
            current_chunk = chunk
        else:
            # 現在の塊が指定長未満なら結合
            if len(current_chunk) < min_len:
                current_chunk += chunk
            else:
                merged_chunks.append(current_chunk)
                current_chunk = chunk
    
    if current_chunk:
        merged_chunks.append(current_chunk)

    # ファイル書き出し
    chunk_paths = []
    base_name = os.path.splitext(os.path.basename(file_path))[0]
    
    print(f"[Splitter] Exporting {len(merged_chunks)} chunks...")
    for i, chunk in enumerate(merged_chunks):
        out_name = f"{base_name}_part{i:03d}.wav"
        out_path = os.path.join(output_dir, out_name)
        chunk.export(out_path, format="wav")
        chunk_paths.append(out_path)
        print(f"  - {out_name}: {len(chunk)/1000:.1f}s")
    
    print(f"[Splitter] Created {len(chunk_paths)} chunks.")
    return chunk_paths