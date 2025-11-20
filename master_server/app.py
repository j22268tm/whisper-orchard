import os
import time
import uuid
from flask import Flask, request, jsonify, render_template
from werkzeug.utils import secure_filename
from core.splitter import split_audio
from core.dispatcher import JobDispatcher
from core.aggregator import aggregate_results
from core.redis_manager import RedisManager
import config

app = Flask(__name__)
app.config['UPLOAD_FOLDER'] = 'uploads'
app.config['CHUNKS_FOLDER'] = 'uploads/chunks'

os.makedirs(app.config['UPLOAD_FOLDER'], exist_ok=True)
os.makedirs(app.config['CHUNKS_FOLDER'], exist_ok=True)

redis_manager = RedisManager()

worker_urls = redis_manager.get_worker_urls()
dispatcher = JobDispatcher(worker_urls, redis_manager)


@app.route('/')
def index():
    return render_template('index.html')


@app.route('/workers', methods=['GET'])
def get_workers():
    online_workers = dispatcher.get_online_workers()
    return jsonify({
        "workers": online_workers,
        "count": len(online_workers)
    })


@app.route('/workers/add', methods=['POST'])
def add_worker():
    data = request.get_json()
    worker_url = data.get('url', '').strip()
    if not worker_url:
        return jsonify({"error": "URLが空です"}), 400
    if not worker_url.startswith(('http://', 'https://')):
        worker_url = 'http://' + worker_url
    workers = redis_manager.get_worker_urls()
    if worker_url in workers:
        return jsonify({"error": "すでに登録されています"}), 400
    redis_manager.add_worker(worker_url)
    workers = redis_manager.get_worker_urls()
    global dispatcher
    dispatcher = JobDispatcher(workers, redis_manager)
    return jsonify({
        "status": "success",
        "workers": workers
    })


@app.route('/workers/remove', methods=['POST'])
def remove_worker():
    data = request.get_json()
    worker_url = data.get('url', '').strip()
    if not worker_url:
        return jsonify({"error": "URLが空です"}), 400
    workers = redis_manager.get_worker_urls()
    if worker_url not in workers:
        return jsonify({"error": "存在しないワーカーです"}), 400
    redis_manager.remove_worker(worker_url)
    workers = redis_manager.get_worker_urls()
    global dispatcher
    dispatcher = JobDispatcher(workers, redis_manager)
    return jsonify({
        "status": "success",
        "workers": workers
    })


@app.route('/preferences/purifier', methods=['POST'])
def set_purifier_preference():
    data = request.get_json()
    use_purifier = data.get('usePurifier', True)
    user_id = 'default_user'
    redis_manager.set_user_preference(user_id, 'use_purifier', use_purifier)
    return jsonify({
        "status": "success",
        "usePurifier": use_purifier
    })

@app.route('/preferences/purifier', methods=['GET'])
def get_purifier_preference():
    user_id = 'default_user'
    use_purifier = redis_manager.get_user_preference(user_id, 'use_purifier', default=True)
    return jsonify({
        "usePurifier": use_purifier
    })

@app.route('/submit', methods=['POST'])
def submit_job():
    if 'file' not in request.files:
        return jsonify({"error": "No file"}), 400
    file = request.files['file']
    if file.filename == '':
        return jsonify({"error": "No filename"}), 400
    
    job_id = str(uuid.uuid4())
    
    filename = secure_filename(file.filename)
    filepath = os.path.join(app.config['UPLOAD_FOLDER'], filename)
    file.save(filepath)
    print(f"[Master] File saved: {filepath}")
    
    user_id = 'default_user'
    use_purifier = redis_manager.get_user_preference(user_id, 'use_purifier', default=True)
    
    redis_manager.create_job(job_id, filename)

    try:
        if use_purifier:
            redis_manager.update_job_status(job_id, 'purifying')
            print("[Master] Purifier: Starting noise reduction (mock)...")
            time.sleep(5)
            print("[Master] Purifier: Complete")
            redis_manager.update_job_status(job_id, 'purifier_completed')
            time.sleep(0.5)
        else:
            print("[Master] Purifier: Bypassed (user preference)")
        
        redis_manager.update_job_status(job_id, 'splitting')
        print("[Master] Orchard: Starting audio splitting...")
        
        chunk_paths = split_audio(
            filepath,
            app.config['CHUNKS_FOLDER'],
            min_len=config.CHUNK_MIN_LENGTH,
            silence_thresh=config.SILENCE_THRESH
        )
        print(f"[Master] Orchard: Created {len(chunk_paths)} chunks")
        
        job_data = redis_manager.get_job_status(job_id)
        if job_data:
            job_data['total_chunks'] = len(chunk_paths)
            redis_manager._set(f"job:{job_id}", redis_manager._get(f"job:{job_id}").replace(
                '"total_chunks": 0', f'"total_chunks": {len(chunk_paths)}'
            ))
        
        redis_manager.update_job_status(job_id, 'processing')

        print("[Master] Orchard: Dispatching to workers...")
        results = []
        chunk_durations_ms = []
        
        for i, chunk in enumerate(chunk_paths):
            chunk_id = f"{job_id}_chunk_{i}"
            print(f"[Master] Orchard: Processing chunk {i+1}/{len(chunk_paths)}...")
            
            from pydub import AudioSegment
            chunk_audio = AudioSegment.from_file(chunk)
            chunk_duration_ms = len(chunk_audio)
            chunk_durations_ms.append(chunk_duration_ms)
            
            res = dispatcher.process_chunk(chunk, job_id, chunk_id)
            if res:
                results.append(res)
            else:
                print(f"[Master] Warning: Chunk {i+1} failed, skipping...")
            
            try:
                os.remove(chunk)
            except Exception as e:
                print(f"[Master] Warning: Failed to delete {chunk}: {e}")

        redis_manager.update_job_status(job_id, 'aggregating')
        print("[Master] Orchard: Aggregating results...")
        final_result = aggregate_results(results, chunk_durations_ms)
        
        try:
            os.remove(filepath)
        except Exception as e:
            print(f"[Master] Warning: Failed to delete {filepath}: {e}")

        redis_manager.update_job_status(job_id, 'completed')
        print("[Master] Complete! Returning result.")
        
        return jsonify({
            "status": "success",
            "job_id": job_id,
            "result": final_result
        })

    except Exception as e:
        import traceback
        print(f"[Master] Error: {e}")
        print(traceback.format_exc())
        redis_manager.update_job_status(job_id, 'failed')
        return jsonify({"status": "error", "message": str(e)}), 500

@app.route('/jobs', methods=['GET'])
def get_jobs():
    jobs = redis_manager.get_all_jobs()
    return jsonify({
        "jobs": jobs,
        "count": len(jobs)
    })

@app.route('/jobs/<job_id>', methods=['GET'])
def get_job_status(job_id):
    job = redis_manager.get_job_status(job_id)
    if job:
        return jsonify(job)
    else:
        return jsonify({"error": "Job not found"}), 404

@app.route('/stats', methods=['GET'])
def get_stats():
    stats = redis_manager.get_stats()
    return jsonify(stats)
    
if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=True, use_reloader=False)
