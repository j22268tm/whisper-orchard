def aggregate_results(results, chunk_durations_ms=None):
    full_text = ""
    total_time_ms = 0
    all_segments = []
    
    current_offset_ms = 0
    
    for i, res in enumerate(results):
        if not res:
            continue
            
        text_part = res.get('text', '').strip()
        if text_part:
            full_text += text_part + "\n"
            
        total_time_ms += res.get('time_ms', 0)
        
        segments = res.get('segments', [])
        for seg in segments:
            corrected_seg = {
                'start': _format_timestamp(seg.get('start_ms', 0) + current_offset_ms),
                'end': _format_timestamp(seg.get('end_ms', 0) + current_offset_ms),
                'start_ms': seg.get('start_ms', 0) + current_offset_ms,
                'end_ms': seg.get('end_ms', 0) + current_offset_ms,
                'text': seg.get('text', '')
            }
            all_segments.append(corrected_seg)
        
        if chunk_durations_ms and i < len(chunk_durations_ms):
            current_offset_ms += chunk_durations_ms[i]
        
    return {
        "text": full_text.strip(),
        "total_processing_time_ms": total_time_ms,
        "segments_count": len(all_segments),
        "segments": all_segments
    }


def _format_timestamp(milliseconds):
    ms = int(milliseconds)
    hours = ms // 3600000
    ms %= 3600000
    minutes = ms // 60000
    ms %= 60000
    seconds = ms // 1000
    ms %= 1000
    return f"{hours:02d}:{minutes:02d}:{seconds:02d}.{ms:03d}"
