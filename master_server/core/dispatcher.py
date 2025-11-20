import requests
import os
import json
import time
import threading

class JobDispatcher:
    def __init__(self, workers, redis_manager=None):
        self.workers = workers
        self.redis_manager = redis_manager
        self._worker_lock = threading.Lock()

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

    def _get_least_busy_worker(self):
        """動的に最も負荷の低いworkerを選択
        1. is_processing=Falseかつonlineのworkerを優先
        2. 次にpending_chunksが最小のworker
        """
        if not self.redis_manager:
            return self.workers[0] if self.workers else None
        
        idle_workers = []
        busy_workers = []
        
        for worker_url in self.workers:
            worker_info = self.redis_manager.get_worker_info(worker_url)
            if worker_info and worker_info.get('status') == 'online':
                if not worker_info.get('is_processing', False):
                    idle_workers.append((worker_url, worker_info.get('pending_chunks', 0)))
                else:
                    busy_workers.append((worker_url, worker_info.get('pending_chunks', 0)))
        
        # 待機中workerがあればそこからpending最小を選ぶ
        if idle_workers:
            idle_workers.sort(key=lambda x: x[1])
            return idle_workers[0][0]
        
        # 全員処理中ならpending最小を選ぶ
        if busy_workers:
            busy_workers.sort(key=lambda x: x[1])
            return busy_workers[0][0]
        
        return self.workers[0] if self.workers else None
    
    def _get_best_worker_for_chunk(self, chunk_duration_sec):
        """チャンク長とworkerパフォーマンスに基づいて最適workerを選択
        - ベンチマーク未実施worker: 最短チャンクで性能測定
        - 高速worker (低いspeed_ratio): 長いチャンク優先
        - 低速worker (高いspeed_ratio): 短いチャンク優先
        """
        if not self.redis_manager:
            return self._get_least_busy_worker()
        
        # ベンチマーク未実施のワーカーを検出
        unbenchmarked_workers = []
        candidates = []
        
        for worker_url in self.workers:
            worker_info = self.redis_manager.get_worker_info(worker_url)
            if not worker_info or worker_info.get('status') != 'online':
                continue
            
            is_processing = worker_info.get('is_processing', False)
            if is_processing:
                continue
            
            performance_history = worker_info.get('performance_history', [])
            
            # 性能データがないワーカーは別扱い
            if not performance_history:
                unbenchmarked_workers.append(worker_url)
                continue
            
            pending = worker_info.get('pending_chunks', 0)
            avg_speed = self.redis_manager.get_worker_avg_speed_ratio(worker_url)
            
            # チャンク長を基準に性能を考慮
            if chunk_duration_sec > 60:
                performance_penalty = avg_speed * 50
            elif chunk_duration_sec < 40:
                performance_penalty = (2.0 - avg_speed) * 50
            else:
                performance_penalty = abs(avg_speed - 1.0) * 30
            
            total_score = pending * 1000 + performance_penalty
            candidates.append((worker_url, total_score, avg_speed))
        
        # ベンチマーク未実施ワーカーがいて、かつ短いチャンク(40秒未満)の場合
        if unbenchmarked_workers and chunk_duration_sec < 40:
            selected = unbenchmarked_workers[0]
            print(f"[Dispatcher] Benchmarking {selected} with {chunk_duration_sec:.1f}s chunk")
            return selected
        
        if not candidates:
            if unbenchmarked_workers:
                selected = unbenchmarked_workers[0]
                print(f"[Dispatcher] Benchmarking {selected} with {chunk_duration_sec:.1f}s chunk")
                return selected
            return self._get_least_busy_worker()
        
        candidates.sort(key=lambda x: x[1])
        selected_worker, score, speed = candidates[0]
        print(f"[Dispatcher] Selected {selected_worker} (speed: {speed:.2f}x) for {chunk_duration_sec:.1f}s chunk")
        return selected_worker

    def process_chunk(self, chunk_path, job_id=None, chunk_id=None, chunk_duration_sec=0):

        # ワーカー選択と is_processing 設定を排他的に実行
        with self._worker_lock:
            worker_url = self._get_best_worker_for_chunk(chunk_duration_sec)
            if not worker_url:
                print("[Dispatcher] No available worker!")
                return None
            
            # 即座に is_processing を True に設定
            if self.redis_manager:
                self.redis_manager.set_worker_processing(worker_url, True)
                self.redis_manager.mark_worker_busy(worker_url, job_id)
                self.redis_manager.increment_worker_pending(worker_url)
            
        endpoint = f"{worker_url}/transcribe"
        params = {"include_formatted_log": "false"}
        
        print(f"[Dispatcher] Sending {os.path.basename(chunk_path)} ({chunk_duration_sec:.1f}s) to {worker_url}...")
        
        if self.redis_manager and job_id and chunk_id:
            self.redis_manager.add_chunk_to_job(job_id, chunk_id, worker_url)
        
        start_time = time.time()
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
            processing_time_sec = time.time() - start_time
            
            if self.redis_manager:
                self.redis_manager.set_worker_processing(worker_url, False)
            
            if response.status_code == 200:
                result = response.json()
                
                if self.redis_manager and job_id and chunk_id:
                    self.redis_manager.complete_chunk(job_id, chunk_id, result)
                    self.redis_manager.mark_worker_idle(worker_url)
                    # pending_chunksをデクリメント
                    self.redis_manager.decrement_worker_pending(worker_url)
                    # パフォーマンス記録
                    self.redis_manager.record_worker_performance(worker_url, chunk_duration_sec, processing_time_sec)
                
                print(f"[Dispatcher] {worker_url} completed in {processing_time_sec:.1f}s (speed: {processing_time_sec/chunk_duration_sec:.2f}x)")
                return result
            else:
                print(f"[Dispatcher] Error from worker: {response.status_code} - {response.text}")
                
                if self.redis_manager:
                    self.redis_manager.set_worker_processing(worker_url, False)
                    self.redis_manager.mark_worker_idle(worker_url)
                    self.redis_manager.decrement_worker_pending(worker_url)
                
                return None
                
        except Exception as e:
            print(f"[Dispatcher] Connection failed: {e}")
            
            if self.redis_manager:
                self.redis_manager.set_worker_processing(worker_url, False)
                self.redis_manager.mark_worker_offline(worker_url)
                self.redis_manager.decrement_worker_pending(worker_url)
            
            return None