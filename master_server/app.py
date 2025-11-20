import os
import time
from flask import Flask, request, jsonify, render_template
from werkzeug.utils import secure_filename
from core.splitter import split_audio
from core.dispatcher import JobDispatcher
from core.aggregator import aggregate_results
import config


app = Flask(__name__)
app.config['UPLOAD_FOLDER'] = 'uploads'
app.config['CHUNKS_FOLDER'] = 'uploads/chunks'
os.makedirs(app.config['UPLOAD_FOLDER'], exist_ok=True)
os.makedirs(app.config['CHUNKS_FOLDER'], exist_ok=True)
dispatcher = JobDispatcher(config.WORKER_NODES)


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
    workers = config.load_worker_nodes()
    if worker_url in workers:
        return jsonify({"error": "すでに登録されています"}), 400
    workers.append(worker_url)
    config.save_worker_nodes(workers)
    global dispatcher
    dispatcher = JobDispatcher(workers)
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
    workers = config.load_worker_nodes()
    if worker_url not in workers:
        return jsonify({"error": "存在しないワーカーです"}), 400
    workers.remove(worker_url)
    config.save_worker_nodes(workers)
    global dispatcher
    dispatcher = JobDispatcher(workers)
    return jsonify({
        "status": "success",
        "workers": workers
    })


@app.route('/submit', methods=['POST'])
def submit_job():
    if 'file' not in request.files:
        return jsonify({"error": "No file"}), 400
    file = request.files['file']
    if file.filename == '':
        return jsonify({"error": "No filename"}), 400
    filename = secure_filename(file.filename)
    filepath = os.path.join(app.config['UPLOAD_FOLDER'], filename)
    file.save(filepath)
    print(f"[Master] File saved: {filepath}")
    try:
        print("[Master] Purifier: Starting noise reduction (mock)...")
        time.sleep(5)
        print("[Master] Purifier: Complete")
        print("[Master] Orchard: Starting audio splitting...")
        chunk_paths = split_audio(
            filepath,
            app.config['CHUNKS_FOLDER'],
            min_len=config.CHUNK_MIN_LENGTH,
            silence_thresh=config.SILENCE_THRESH
        )
        print(f"[Master] Orchard: Created {len(chunk_paths)} chunks")
        print("[Master] Orchard: Dispatching to workers...")
        results = []
        chunk_durations_ms = []
        for i, chunk in enumerate(chunk_paths):
            print(f"[Master] Orchard: Processing chunk {i+1}/{len(chunk_paths)}...")
            from pydub import AudioSegment
            chunk_audio = AudioSegment.from_file(chunk)
            chunk_duration_ms = len(chunk_audio)
            chunk_durations_ms.append(chunk_duration_ms)
            res = dispatcher.process_chunk(chunk)
            if res:
                results.append(res)
            else:
                print(f"[Master] Warning: Chunk {i+1} failed, skipping...")
            try:
                os.remove(chunk)
            except Exception as e:
                print(f"[Master] Warning: Failed to delete {chunk}: {e}")
        print("[Master] Orchard: Aggregating results...")
        final_result = aggregate_results(results, chunk_durations_ms)
        try:
            os.remove(filepath)
        except Exception as e:
            print(f"[Master] Warning: Failed to delete {filepath}: {e}")
        print("[Master] Complete! Returning result.")
        return jsonify({
            "status": "success",
            "result": final_result
        })
    except Exception as e:
        import traceback
        print(f"[Master] Error: {e}")
        print(traceback.format_exc())
        return jsonify({"status": "error", "message": str(e)}), 500
    
if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=True, use_reloader=False)
