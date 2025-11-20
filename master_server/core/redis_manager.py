import redis
import json
import time
from datetime import datetime, timedelta

class RedisManager:

    def __init__(self, host='localhost', port=6379, db=0):

        self.use_redis = True
        try:
            self.redis = redis.Redis(host=host, port=port, db=db, decode_responses=True)
            self.redis.ping()
            print("[Redis] Connected successfully")
        except Exception as e:
            print(f"[Redis] Connection failed: {e}")
            print("[Redis] Fallback to in-memory mode")
            self.use_redis = False
            self._memory_store = {}
    
    def _set(self, key, value, ex=None):
        if self.use_redis:
            self.redis.set(key, value, ex=ex)
        else:
            self._memory_store[key] = value
    
    def _get(self, key):
        if self.use_redis:
            return self.redis.get(key)
        else:
            return self._memory_store.get(key)
    
    def _delete(self, key):
        if self.use_redis:
            self.redis.delete(key)
        else:
            self._memory_store.pop(key, None)
    
    def _keys(self, pattern):
        if self.use_redis:
            return self.redis.keys(pattern)
        else:
            import fnmatch
            return [k for k in self._memory_store.keys() if fnmatch.fnmatch(k, pattern)]
    
    
    def update_worker_status(self, worker_url, status='online', metadata=None):

        key = f"worker:{worker_url}"
        data = {
            'url': worker_url,
            'status': status,
            'last_updated': datetime.now().isoformat(),
            'metadata': metadata or {}
        }
        self._set(key, json.dumps(data), ex=300)
    
    def get_worker_status(self, worker_url):
        key = f"worker:{worker_url}"
        data = self._get(key)
        if data:
            return json.loads(data)
        return None
    
    def get_all_workers(self):
        keys = self._keys("worker:*")
        workers = []
        for key in keys:
            data = self._get(key)
            if data:
                workers.append(json.loads(data))
        return workers
    
    def mark_worker_offline(self, worker_url):
        self.update_worker_status(worker_url, status='offline')
    
    def mark_worker_busy(self, worker_url, job_id):
        self.update_worker_status(worker_url, status='busy', metadata={'job_id': job_id})
    
    def mark_worker_idle(self, worker_url):
        self.update_worker_status(worker_url, status='online')
    
    def add_worker(self, worker_url):
        self.update_worker_status(worker_url, status='online')
    
    def remove_worker(self, worker_url):
        key = f"worker:{worker_url}"
        self._delete(key)
    
    def get_worker_urls(self):
        workers = self.get_all_workers()
        return [w['url'] for w in workers]
    
    
    def set_user_preference(self, user_id, key, value):

        redis_key = f"user_pref:{user_id}:{key}"
        self._set(redis_key, json.dumps(value), ex=86400)
    
    def get_user_preference(self, user_id, key, default=None):

        redis_key = f"user_pref:{user_id}:{key}"
        data = self._get(redis_key)
        if data:
            return json.loads(data)
        return default
    
    def create_job(self, job_id, filename, total_chunks=0):
        key = f"job:{job_id}"
        data = {
            'job_id': job_id,
            'filename': filename,
            'status': 'created',
            'total_chunks': total_chunks,
            'completed_chunks': 0,
            'created_at': datetime.now().isoformat(),
            'updated_at': datetime.now().isoformat(),
            'chunks': []
        }
        self._set(key, json.dumps(data), ex=3600)
        return job_id
    
    def update_job_status(self, job_id, status):
        key = f"job:{job_id}"
        data = self._get(key)
        if data:
            job_data = json.loads(data)
            job_data['status'] = status
            job_data['updated_at'] = datetime.now().isoformat()
            self._set(key, json.dumps(job_data), ex=3600)
    
    def add_chunk_to_job(self, job_id, chunk_id, worker_url):
        key = f"job:{job_id}"
        data = self._get(key)
        if data:
            job_data = json.loads(data)
            chunk_info = {
                'chunk_id': chunk_id,
                'worker_url': worker_url,
                'status': 'processing',
                'started_at': datetime.now().isoformat()
            }
            job_data['chunks'].append(chunk_info)
            job_data['updated_at'] = datetime.now().isoformat()
            self._set(key, json.dumps(job_data), ex=3600)
    
    def complete_chunk(self, job_id, chunk_id, result=None):
        key = f"job:{job_id}"
        data = self._get(key)
        if data:
            job_data = json.loads(data)
            for chunk in job_data['chunks']:
                if chunk['chunk_id'] == chunk_id:
                    chunk['status'] = 'completed'
                    chunk['completed_at'] = datetime.now().isoformat()
                    if result:
                        chunk['result_summary'] = {
                            'text_length': len(result.get('text', '')),
                            'segments_count': len(result.get('segments', []))
                        }
                    break
            
            job_data['completed_chunks'] = sum(
                1 for c in job_data['chunks'] if c['status'] == 'completed'
            )
            job_data['updated_at'] = datetime.now().isoformat()
            
            if job_data['completed_chunks'] == job_data['total_chunks']:
                job_data['status'] = 'aggregating'
            
            self._set(key, json.dumps(job_data), ex=3600)
    
    def get_job_status(self, job_id):
        key = f"job:{job_id}"
        data = self._get(key)
        if data:
            return json.loads(data)
        return None
    
    def get_all_jobs(self, limit=50):
        keys = self._keys("job:*")
        jobs = []
        for key in keys:
            data = self._get(key)
            if data:
                jobs.append(json.loads(data))
        
        jobs.sort(key=lambda x: x.get('created_at', ''), reverse=True)
        return jobs[:limit]
    
    def delete_job(self, job_id):
        key = f"job:{job_id}"
        self._delete(key)
    
    
    def get_stats(self):
        workers = self.get_all_workers()
        jobs = self.get_all_jobs()
        
        online_workers = sum(1 for w in workers if w['status'] == 'online')
        busy_workers = sum(1 for w in workers if w['status'] == 'busy')
        
        active_jobs = sum(1 for j in jobs if j['status'] in ['processing', 'aggregating'])
        completed_jobs = sum(1 for j in jobs if j['status'] == 'completed')
        
        return {
            'workers': {
                'total': len(workers),
                'online': online_workers,
                'busy': busy_workers,
                'offline': len(workers) - online_workers - busy_workers
            },
            'jobs': {
                'total': len(jobs),
                'active': active_jobs,
                'completed': completed_jobs
            }
        }
