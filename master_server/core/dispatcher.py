import requests
import os
import json

class JobDispatcher:
    def __init__(self, workers, redis_manager=None):
        self.workers = workers
        self.current_worker_index = 0
        self.redis_manager = redis_manager

    def get_online_workers(self):
        online = []
        for i, worker_url in enumerate(self.workers):
            try:
                response = requests.get(f"{worker_url}/", timeout=2)
                if response.status_code == 200 or response.status_code == 404:
                    online.append({
                        "id": i + 1,
                        "url": worker_url,
                        "status": "online"
                    })
                    if self.redis_manager:
                        self.redis_manager.update_worker_status(worker_url, 'online')
            except:
                if self.redis_manager:
                    self.redis_manager.mark_worker_offline(worker_url)
        return online

    def _get_next_worker(self):
        # roundrobin
        worker = self.workers[self.current_worker_index]
        self.current_worker_index = (self.current_worker_index + 1) % len(self.workers)
        return worker

    def process_chunk(self, chunk_path, job_id=None, chunk_id=None):

        worker_url = self._get_next_worker()
        endpoint = f"{worker_url}/transcribe"
        
        params = {"include_formatted_log": "false"}
        
        print(f"[Dispatcher] Sending {os.path.basename(chunk_path)} to {worker_url}...")
        
        if self.redis_manager and job_id and chunk_id:
            self.redis_manager.add_chunk_to_job(job_id, chunk_id, worker_url)
            self.redis_manager.mark_worker_busy(worker_url, job_id)
        
        try:
            with open(chunk_path, 'rb') as f:
                headers = {'Content-Type': 'audio/wav'}
                response = requests.post(
                    endpoint, 
                    data=f, 
                    headers=headers, 
                    params=params,
                    timeout=600000
                )
                
            if response.status_code == 200:
                result = response.json()
                
                if self.redis_manager and job_id and chunk_id:
                    self.redis_manager.complete_chunk(job_id, chunk_id, result)
                    self.redis_manager.mark_worker_idle(worker_url)
                
                return result
            else:
                print(f"[Dispatcher] Error from worker: {response.status_code} - {response.text}")
                
                if self.redis_manager:
                    self.redis_manager.mark_worker_idle(worker_url)
                
                return None
                
        except Exception as e:
            print(f"[Dispatcher] Connection failed: {e}")
            
            if self.redis_manager:
                self.redis_manager.mark_worker_offline(worker_url)
            
            return None